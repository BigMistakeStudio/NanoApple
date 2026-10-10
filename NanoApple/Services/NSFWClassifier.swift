// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

actor NSFWClassifier {
    private struct Result: Decodable {
        let nsfwProbability: Double
    }

    private var activeProcess: Process?

    func classify(
        imageURL: URL,
        modelRoot: URL,
        runtimeModelRoot: URL,
        outputDirectory: URL
    ) async throws -> Double {
        guard let script = Bundle.main.url(forResource: "nsfw_classifier", withExtension: "py"),
              let python = RuntimeInstaller.bundledPythonURL(),
              let libraryRoot = runtimeLibraryRoot(for: runtimeModelRoot) else {
            throw ImageGenerationError.engineNotInstalled
        }
        for filename in ["config.json", "preprocessor_config.json", "model.safetensors"] {
            guard FileManager.default.fileExists(atPath: modelRoot.appending(path: filename).path) else {
                throw ImageGenerationError.nsfwClassifierNotInstalled
            }
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let suffix = UUID().uuidString
        let resultURL = outputDirectory.appending(path: ".nanoapple-nsfw-result-\(suffix).json")
        let logURL = outputDirectory.appending(path: ".nanoapple-nsfw-\(suffix).log")
        defer {
            try? FileManager.default.removeItem(at: resultURL)
            try? FileManager.default.removeItem(at: logURL)
        }

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }

        let process = Process()
        process.executableURL = python
        process.arguments = [
            script.path, "--model", modelRoot.path,
            "--image", imageURL.path, "--output", resultURL.path
        ]
        process.standardOutput = log
        process.standardError = log
        var environment = ProcessInfo.processInfo.environment.merging([
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONNOUSERSITE": "1",
            "PYTHONPATH": RuntimeInstaller.packagesDirectory(in: libraryRoot).path,
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1"
        ]) { _, new in new }
        for key in Array(environment.keys) where key.hasPrefix("MTL_DEBUG_LAYER") {
            environment.removeValue(forKey: key)
        }
        process.environment = environment

        do {
            try Task.checkCancellation()
            try process.run()
            activeProcess = process
            while process.isRunning {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(200))
            }
            activeProcess = nil
            try Task.checkCancellation()
            try? log.synchronize()
            guard process.terminationStatus == 0,
                  let data = try? Data(contentsOf: resultURL),
                  let result = try? JSONDecoder().decode(Result.self, from: data),
                  result.nsfwProbability.isFinite,
                  (0...1).contains(result.nsfwProbability) else {
                let output = String(decoding: (try? Data(contentsOf: logURL)) ?? Data(), as: UTF8.self)
                throw ImageGenerationError.executionFailed(output.isEmpty
                    ? String(localized: "error.nsfw_no_result", defaultValue: "Le filtre NSFW n’a pas renvoyé de résultat.")
                    : output)
            }
            return result.nsfwProbability
        } catch {
            terminateActiveProcess()
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
