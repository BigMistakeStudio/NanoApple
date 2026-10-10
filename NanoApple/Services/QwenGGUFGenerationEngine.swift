// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

actor QwenGGUFGenerationEngine: ImageGenerationEngine {
    let identifier: String
    private let variant: QwenTurboGGUFVariant

    init(variant: QwenTurboGGUFVariant) {
        self.variant = variant
        identifier = variant == .q8 ? "nanoapple.qwen-image-2.1.turbo-q8-metal"
            : "nanoapple.qwen-image-2.1.turbo-atomic-q5-metal"
    }

    private var activeProcess: Process?
    private var preparedModelRoot: URL?
    private var executableURL: URL?

    func prepare(modelRoot: URL) async throws {
        if preparedModelRoot != nil, preparedModelRoot != modelRoot {
            await unload()
        }
        guard let executable = Bundle.main.url(
            forResource: "sd-cli",
            withExtension: nil,
            subdirectory: "GGUF"
        ), FileManager.default.isExecutableFile(atPath: executable.path) else {
            await AppLog.shared.append(.error, category: "GGUF", String(localized: "error.gguf_engine_missing", defaultValue: "Le moteur stable-diffusion.cpp embarqué est introuvable."))
            throw ImageGenerationError.engineNotInstalled
        }

        for relativePath in variant.requiredFiles {
            let file = modelRoot.appending(path: relativePath)
            guard FileManager.default.fileExists(atPath: file.path) else {
                await AppLog.shared.append(.error, category: "GGUF", "Fichier requis absent : \(relativePath)")
                throw ImageGenerationError.modelNotInstalled
            }
        }

        executableURL = executable
        preparedModelRoot = modelRoot
        await AppLog.shared.append(category: "GGUF", "Modèle Qwen Turbo GGUF prêt pour \(modelRoot.path).")
    }

    func generate(
        request: GenerationRequest,
        outputDirectory: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard let executable = executableURL, let modelRoot = preparedModelRoot else {
            throw ImageGenerationError.engineNotInstalled
        }
        guard request.mode != .viewpointOrbit, request.useViggleTurbo != true,
              request.useConsistencyLoRA != true else {
            throw ImageGenerationError.unsupportedConfiguration
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let identifier = request.id.uuidString
        let outputURL = outputDirectory.appending(path: "NanoApple-\(identifier).png")
        let logURL = outputDirectory.appending(path: ".nanoapple-gguf-\(identifier).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)

        defer {
            try? log.close()
            try? FileManager.default.removeItem(at: logURL)
        }

        let usesReducedMemoryMode = ProcessInfo.processInfo.physicalMemory < 32 * 1_024 * 1_024 * 1_024
        let arguments = variant.arguments(request: request, modelRoot: modelRoot,
                                          outputURL: outputURL, reducedMemory: usesReducedMemoryMode)
        if usesReducedMemoryMode {
            await AppLog.shared.append(category: "GGUF", "Mode mémoire réduite : segmentation Metal et VAE tuilé.")
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = executable.deletingLastPathComponent()
        process.standardOutput = log
        process.standardError = log
        var environment = ProcessInfo.processInfo.environment
        for key in Array(environment.keys) where key.hasPrefix("MTL_DEBUG_LAYER") {
            environment.removeValue(forKey: key)
        }
        process.environment = environment

        await AppLog.shared.append(
            category: "GGUF",
            "Début \(identifier) — \(request.width)×\(request.height), 8 étapes, \(request.referenceImages.count) référence(s)."
        )

        do {
            progress(0.01)
            try process.run()
            activeProcess = process

            var lastProgress = 0.01
            while process.isRunning {
                try Task.checkCancellation()
                if let data = try? Data(contentsOf: logURL),
                   let stepProgress = Self.stepProgress(in: data, stepCount: 8) {
                    lastProgress = max(lastProgress, 0.08 + (stepProgress * 0.88))
                    progress(lastProgress)
                }
                try await Task.sleep(for: .milliseconds(400))
            }

            activeProcess = nil
            try Task.checkCancellation()
            try? log.synchronize()
            let engineOutput = String(decoding: (try? Data(contentsOf: logURL)) ?? Data(), as: UTF8.self)
            await AppLog.shared.append(category: "GGUF output", engineOutput)

            guard process.terminationStatus == 0,
                  FileManager.default.fileExists(atPath: outputURL.path) else {
                let message = engineOutput.isEmpty
                    ? String(localized: "error.gguf_no_image", defaultValue: "Le modèle GGUF s’est arrêté sans produire d’image.")
                    : engineOutput
                throw ImageGenerationError.executionFailed(message)
            }

            progress(1)
            await AppLog.shared.append(category: "GGUF", "Image créée : \(outputURL.path)")
            return outputURL
        } catch is CancellationError {
            terminateActiveProcess()
            await AppLog.shared.append(.warning, category: "GGUF", "Génération \(identifier) annulée.")
            throw CancellationError()
        } catch {
            terminateActiveProcess()
            await AppLog.shared.append(.error, category: "GGUF", error.localizedDescription)
            throw error
        }
    }

    func cancel() async {
        terminateActiveProcess()
    }

    func unload() async {
        terminateActiveProcess()
        preparedModelRoot = nil
        executableURL = nil
        await AppLog.shared.append(category: "GGUF", "Modèle GGUF déchargé.")
    }

    private func terminateActiveProcess() {
        guard let process = activeProcess else { return }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        activeProcess = nil
    }

    private static func stepProgress(in data: Data, stepCount: Int) -> Double? {
        let text = String(decoding: data, as: UTF8.self)
        guard let expression = try? NSRegularExpression(pattern: #"(\d+)\s*/\s*(\d+)"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var best: Double?

        for match in expression.matches(in: text, range: range) {
            guard match.numberOfRanges == 3,
                  let currentRange = Range(match.range(at: 1), in: text),
                  let totalRange = Range(match.range(at: 2), in: text),
                  let current = Int(text[currentRange]),
                  let total = Int(text[totalRange]),
                  total == stepCount,
                  current <= total else { continue }
            best = max(best ?? 0, Double(current) / Double(max(total, 1)))
        }
        return best
    }
}

private extension GenerationRequest {
    var requestsTransparency: Bool { mode.requestsTransparency }
}
