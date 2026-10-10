// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

protocol ImageGenerationEngine: Sendable {
    var identifier: String { get }
    func prepare(modelRoot: URL) async throws
    func generate(
        request: GenerationRequest,
        outputDirectory: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL
    func cancel() async
    func unload() async
}

enum ImageGenerationError: LocalizedError {
    case engineNotInstalled
    case modelNotInstalled
    case promptEnhancerNotInstalled
    case nsfwClassifierNotInstalled
    case externalStorageUnavailable
    case unsupportedConfiguration
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .engineNotInstalled:
            String(localized: "error.engine_not_installed", defaultValue: "Le runtime du modèle sélectionné est absent ou endommagé.")
        case .modelNotInstalled:
            String(localized: "error.model_not_installed", defaultValue: "Les poids Qwen-Image 2.1 sont absents.")
        case .promptEnhancerNotInstalled:
            String(localized: "error.prompt_enhancer_not_installed", defaultValue: "Installez Qwen Prompt Enhancers dans Modèles pour améliorer le prompt.")
        case .nsfwClassifierNotInstalled:
            String(localized: "error.nsfw_classifier_not_installed", defaultValue: "Installez le filtre NSFW dans Modèles ou désactivez-le dans Réglages.")
        case .externalStorageUnavailable:
            String(localized: "error.storage_unavailable", defaultValue: "Le support de stockage sélectionné n’est pas disponible.")
        case .unsupportedConfiguration:
            String(localized: "error.unsupported_configuration", defaultValue: "Cette configuration n’est pas encore prise en charge.")
        case .executionFailed(let message):
            message
        }
    }
}

actor QwenPythonGenerationEngine: ImageGenerationEngine {
    let identifier: String
    private let textEncoderPackageID: String?
    private let officialTurbo: Bool
    private var activeProcess: Process?
    private var preparedModelRoot: URL?
    private var preparedLibraryRoot: URL?
    private var preparedTextEncoderURL: URL?

    init(textEncoderPackageID: String? = nil, officialTurbo: Bool = false) {
        self.officialTurbo = officialTurbo
        self.textEncoderPackageID = textEncoderPackageID
        identifier = officialTurbo ? "nanoapple.qwen-image-2.1.turbo-mps" : textEncoderPackageID == nil
            ? "nanoapple.qwen-image-2.1.diffusers-mps"
            : "nanoapple.qwen-image-2.1.diffusers-heretic-mps"
    }

    func prepare(modelRoot: URL) async throws {
        if preparedModelRoot != nil, preparedModelRoot != modelRoot {
            await unload()
        }
        guard let libraryRoot = runtimeLibraryRoot(for: modelRoot),
              RuntimeInstaller.bundledPythonURL() != nil else {
            await AppLog.shared.append(.error, category: "Generation", String(localized: "error.python_missing", defaultValue: "Le runtime Python est introuvable pour le modèle \(modelRoot.lastPathComponent)."))
            throw ImageGenerationError.engineNotInstalled
        }
        guard Bundle.main.url(forResource: "qwen_runtime", withExtension: "py") != nil else {
            await AppLog.shared.append(.error, category: "Generation", String(localized: "error.runtime_script_missing", defaultValue: "Le script qwen_runtime.py est absent du paquet de l’application."))
            throw ImageGenerationError.engineNotInstalled
        }
        if let textEncoderPackageID {
            let encoderURL = modelRoot.deletingLastPathComponent()
                .appending(path: textEncoderPackageID, directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: encoderURL.appending(path: "config.json").path),
                  FileManager.default.fileExists(atPath: encoderURL.appending(path: "model.safetensors.index.json").path) else {
                throw ImageGenerationError.modelNotInstalled
            }
            preparedTextEncoderURL = encoderURL
        } else {
            preparedTextEncoderURL = nil
        }
        preparedModelRoot = modelRoot
        preparedLibraryRoot = libraryRoot
        await AppLog.shared.append(category: "Generation", "Modèle Qwen prêt pour \(modelRoot.path).")
    }

    func generate(
        request: GenerationRequest,
        outputDirectory: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard let modelRoot = preparedModelRoot,
              let runner = Bundle.main.url(forResource: "qwen_runtime", withExtension: "py") else {
            throw ImageGenerationError.engineNotInstalled
        }

        guard let libraryRoot = preparedLibraryRoot,
              let python = RuntimeInstaller.bundledPythonURL() else {
            throw ImageGenerationError.engineNotInstalled
        }
        if (request.useViggleTurbo == true || request.mode == .viewpointOrbit)
            && !RuntimeInstaller.isReady(in: libraryRoot) {
            throw ImageGenerationError.engineNotInstalled
        }
        let packages = RuntimeInstaller.packagesDirectory(in: libraryRoot)

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let identifier = request.id.uuidString
        let requestURL = outputDirectory.appending(path: ".nanoapple-request-\(identifier).json")
        let statusURL = outputDirectory.appending(path: ".nanoapple-status-\(identifier).json")
        let outputURL = outputDirectory.appending(path: "NanoApple-\(identifier).png")
        let logURL = outputDirectory.appending(path: ".nanoapple-runtime-\(identifier).log")

        await AppLog.shared.append(
            category: "Generation",
            "Début \(identifier) — \(request.width)×\(request.height), \(request.steps) étapes."
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(request).write(to: requestURL, options: .atomic)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        defer {
            try? log.close()
            try? FileManager.default.removeItem(at: requestURL)
            try? FileManager.default.removeItem(at: statusURL)
            try? FileManager.default.removeItem(at: logURL)
        }

        let process = Process()
        process.executableURL = python
        var arguments = [
            runner.path,
            "--model", modelRoot.path,
            "--request", requestURL.path,
            "--output", outputURL.path,
            "--status", statusURL.path
        ]
        if officialTurbo {
            guard request.mode != .viewpointOrbit,
                  request.useViggleTurbo != true, request.useConsistencyLoRA != true,
                  textEncoderPackageID == nil else {
                throw ImageGenerationError.unsupportedConfiguration
            }
            arguments.append("--official-turbo")
        }
        if let preparedTextEncoderURL {
            arguments.append(contentsOf: ["--text-encoder", preparedTextEncoderURL.path])
        }
        if request.mode == .viewpointOrbit {
            guard textEncoderPackageID == nil,
                  let settings = request.viewpointOrbit, settings.isValid,
                  request.referenceImages.count == 1,
                  request.width == 768, request.height == 768, request.steps == 40,
                  !request.enhancePrompt, request.enhancedPrompt == nil,
                  request.useViggleTurbo != true, request.useConsistencyLoRA != true,
                  request.maskImage == nil else {
                throw ImageGenerationError.unsupportedConfiguration
            }
            let adapter = modelRoot.deletingLastPathComponent()
                .appending(path: ModelPackage.viewpointOrbit.id, directoryHint: .isDirectory)
                .appending(path: ModelPackage.viewpointOrbitWeightPath)
            guard FileManager.default.fileExists(atPath: adapter.path) else {
                throw ImageGenerationError.modelNotInstalled
            }
            arguments.append(contentsOf: ["--viewpoint-orbit", adapter.path])
        }
        if request.useViggleTurbo == true {
            guard textEncoderPackageID == nil else {
                throw ImageGenerationError.unsupportedConfiguration
            }
            let adapter = modelRoot.deletingLastPathComponent()
                .appending(path: ModelPackage.viggleTurbo.id, directoryHint: .isDirectory)
                .appending(path: "Qwen-Image-2.1-viggle-turbo-v0.2.1-6step-lora-r128.safetensors")
            guard FileManager.default.fileExists(atPath: adapter.path) else {
                throw ImageGenerationError.modelNotInstalled
            }
            arguments.append(contentsOf: ["--viggle-turbo", adapter.path])
        }
        if request.useConsistencyLoRA == true {
            guard textEncoderPackageID == nil,
                  request.useViggleTurbo != true,
                  request.mode == .edit,
                  request.referenceImages.count == 1 else {
                throw ImageGenerationError.unsupportedConfiguration
            }
            let adapter = modelRoot.deletingLastPathComponent()
                .appending(path: ModelPackage.consistencyLoRA.id, directoryHint: .isDirectory)
                .appending(path: "qwen-image-2.1-consistency.safetensors")
            guard FileManager.default.fileExists(atPath: adapter.path) else {
                throw ImageGenerationError.modelNotInstalled
            }
            arguments.append(contentsOf: ["--consistency-lora", adapter.path])
        }
        process.arguments = arguments
        process.standardOutput = log
        process.standardError = log
        var environment = ProcessInfo.processInfo.environment.merging([
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONNOUSERSITE": "1",
            "PYTHONPATH": packages.path
        ]) { _, new in new }
        // Xcode enables its Metal validation layer in Debug and passes those
        // variables to child processes. PyTorch's private MPS shaders do not
        // satisfy that layer's argument checks and are aborted even though
        // they execute correctly without the debugger. Never inherit Xcode's
        // validation layer in the standalone generation process.
        for key in Array(environment.keys) where key.hasPrefix("MTL_DEBUG_LAYER") {
            environment.removeValue(forKey: key)
        }
        process.environment = environment

        do {
            try process.run()
            activeProcess = process
            while process.isRunning {
                if let data = try? Data(contentsOf: statusURL),
                   let status = try? JSONDecoder().decode(QwenRuntimeStatus.self, from: data),
                   let value = status.progress {
                    progress(value)
                }
                try await Task.sleep(for: .milliseconds(400))
            }
            activeProcess = nil
            try Task.checkCancellation()

            try? log.synchronize()
            let runtimeOutput = String(decoding: (try? Data(contentsOf: logURL)) ?? Data(), as: UTF8.self)
            await AppLog.shared.append(category: "Qwen output", runtimeOutput)

            guard process.terminationStatus == 0,
                  FileManager.default.fileExists(atPath: outputURL.path) else {
                let message = runtimeOutput.isEmpty ? String(localized: "error.diffusers_no_image", defaultValue: "Le processus Qwen s’est arrêté sans produire d’image.") : runtimeOutput
                await AppLog.shared.append(.error, category: "Generation", "Échec \(identifier) : \(message)")
                throw ImageGenerationError.executionFailed(message)
            }
            progress(1)
            await AppLog.shared.append(category: "Generation", "Image créée : \(outputURL.path)")
            return outputURL
        } catch is CancellationError {
            terminateActiveProcess()
            await AppLog.shared.append(.warning, category: "Generation", "Génération \(identifier) annulée.")
            throw CancellationError()
        } catch {
            activeProcess = nil
            await AppLog.shared.append(.error, category: "Generation", error.localizedDescription)
            throw error
        }
    }

    func cancel() async {
        terminateActiveProcess()
    }

    func unload() async {
        terminateActiveProcess()
        preparedModelRoot = nil
        preparedLibraryRoot = nil
        preparedTextEncoderURL = nil
        await AppLog.shared.append(category: "Generation", "Modèle Qwen complet déchargé.")
    }

    private func terminateActiveProcess() {
        guard let process = activeProcess else { return }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        activeProcess = nil
    }

    private func runtimeLibraryRoot(for modelRoot: URL) -> URL? {
        let parent = modelRoot.deletingLastPathComponent()
        let candidates = [
            modelRoot,
            parent,
            parent.deletingLastPathComponent()
        ]
        return candidates.first { RuntimeInstaller.isReady(in: $0) }
    }
}

private struct QwenRuntimeStatus: Decodable {
    let progress: Double?
}

/// Point d'intégration du futur processus local Diffusers/MLX.
/// L'interface ne dépend pas de son implémentation concrète.
struct UnavailableGenerationEngine: ImageGenerationEngine {
    let identifier = "nanoapple.qwen-image-2.1.placeholder"

    func prepare(modelRoot: URL) async throws {
        throw ImageGenerationError.engineNotInstalled
    }

    func generate(
        request: GenerationRequest,
        outputDirectory: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        throw ImageGenerationError.engineNotInstalled
    }

    func cancel() async {}
    func unload() async {}
}
