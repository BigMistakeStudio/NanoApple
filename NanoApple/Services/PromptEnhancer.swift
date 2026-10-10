// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

actor PromptEnhancer {
    private var activeProcess: Process?

    func enhance(
        request: GenerationRequest,
        modelRoot: URL,
        runtimeModelRoot: URL,
        outputDirectory: URL
    ) async throws -> String {
        guard let script = Bundle.main.url(forResource: "prompt_enhancer", withExtension: "py"),
              let python = RuntimeInstaller.bundledPythonURL(),
              let libraryRoot = runtimeLibraryRoot(for: runtimeModelRoot) else {
            throw ImageGenerationError.engineNotInstalled
        }
        let modelDirectory = modelRoot.appending(
            path: request.referenceImages.isEmpty ? "text-to-image" : "image-to-image",
            directoryHint: .isDirectory
        )
        guard FileManager.default.fileExists(atPath: modelDirectory.appending(path: "config.json").path),
              FileManager.default.fileExists(atPath: modelDirectory.appending(path: "system_prompt.txt").path) else {
            throw ImageGenerationError.promptEnhancerNotInstalled
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let suffix = request.id.uuidString
        let requestURL = outputDirectory.appending(path: ".nanoapple-enhancer-request-\(suffix).json")
        let resultURL = outputDirectory.appending(path: ".nanoapple-enhancer-result-\(suffix).json")
        let logURL = outputDirectory.appending(path: ".nanoapple-enhancer-\(suffix).log")
        defer {
            try? FileManager.default.removeItem(at: requestURL)
            try? FileManager.default.removeItem(at: resultURL)
            try? FileManager.default.removeItem(at: logURL)
        }

        try JSONEncoder().encode(request).write(to: requestURL, options: .atomic)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }

        let process = Process()
        process.executableURL = python
        process.arguments = [
            script.path, "--model", modelRoot.path,
            "--request", requestURL.path, "--output", resultURL.path
        ]
        process.standardOutput = log
        process.standardError = log
        var environment = ProcessInfo.processInfo.environment.merging([
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONNOUSERSITE": "1",
            "PYTHONPATH": RuntimeInstaller.packagesDirectory(in: libraryRoot).path
        ]) { _, new in new }
        for key in Array(environment.keys) where key.hasPrefix("MTL_DEBUG_LAYER") {
            environment.removeValue(forKey: key)
        }
        process.environment = environment

        await AppLog.shared.append(category: "Prompt Enhancer", "Début de la réécriture du prompt \(suffix).")
        do {
            try Task.checkCancellation()
            try process.run()
            activeProcess = process
            while process.isRunning {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(400))
            }
            activeProcess = nil
            try Task.checkCancellation()
            try? log.synchronize()
            guard process.terminationStatus == 0,
                  let data = try? Data(contentsOf: resultURL),
                  let result = try? JSONDecoder().decode(PromptEnhancerResult.self, from: data),
                  !result.enhancedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                let output = String(decoding: (try? Data(contentsOf: logURL)) ?? Data(), as: UTF8.self)
                throw ImageGenerationError.executionFailed(output.isEmpty
                    ? String(localized: "error.enhancer_no_result", defaultValue: "L’améliorateur de prompt n’a pas renvoyé de résultat.")
                    : output)
            }
            await AppLog.shared.append(category: "Prompt Enhancer", "Prompt enrichi pour \(suffix).")
            return result.enhancedPrompt
        } catch is CancellationError {
            terminateActiveProcess()
            await AppLog.shared.append(.warning, category: "Prompt Enhancer", "Réécriture annulée : \(suffix).")
            throw CancellationError()
        } catch {
            terminateActiveProcess()
            await AppLog.shared.append(.error, category: "Prompt Enhancer", error.localizedDescription)
            throw error
        }
    }

    func cancel() {
        terminateActiveProcess()
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
        return [modelRoot, parent, parent.deletingLastPathComponent()]
            .first { RuntimeInstaller.isReady(in: $0) }
    }
}

private struct PromptEnhancerResult: Decodable {
    let enhancedPrompt: String
}
