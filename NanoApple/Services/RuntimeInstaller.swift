import Foundation

@MainActor
final class RuntimeInstaller: ObservableObject {
    private static let diffusersRevision = "cc8644b447d8f11074d3df06d0ee0e3e7c91bf75"

    enum State: Equatable {
        case unavailable
        case installing(String)
        case ready
        case failed(String)

        var isInstalling: Bool {
            if case .installing = self { return true }
            return false
        }
    }

    @Published private(set) var state: State = .unavailable

    private var task: Task<Void, Never>?

    func refresh(in libraryRoot: URL?) {
        guard let libraryRoot else {
            state = .unavailable
            return
        }
        state = Self.isReady(in: libraryRoot) ? .ready : .unavailable
    }

    func install(in libraryRoot: URL) {
        guard task == nil, let uv = locateUV(), let python = Self.bundledPythonURL() else {
            if task == nil {
                let message = String(localized: "runtime.error.tools", defaultValue: "Le runtime Python ou l’exécutable uv embarqué est introuvable.")
                state = .failed(message)
                Task { await AppLog.shared.append(.error, category: "Runtime", message) }
            }
            return
        }

        let runtime = Self.runtimeDirectory(in: libraryRoot)
        let packages = Self.packagesDirectory(in: libraryRoot)
        let support = libraryRoot.appending(path: ".NanoAppleRuntimeSupport", directoryHint: .isDirectory)
        let environment = [
            "UV_CACHE_DIR": support.appending(path: "cache", directoryHint: .isDirectory).path,
            "UV_PYTHON_DOWNLOADS": "never",
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONNOUSERSITE": "1",
            "PYTHONPATH": packages.path
        ]
        task = Task { [weak self] in
            guard let self else { return }
            do {
                await AppLog.shared.append(category: "Runtime", "Début de l’installation dans \(runtime.path)")
                try FileManager.default.createDirectory(at: packages, withIntermediateDirectories: true)

                let hasPreviousRuntime = FileManager.default.fileExists(
                    atPath: runtime.appending(path: ".ready-v3").path
                ) && FileManager.default.fileExists(atPath: packages.appending(path: "diffusers").path)
                state = .installing(String(localized: "runtime.install.packages", defaultValue: "Installation de PyTorch Metal et Diffusers…"))
                var packagesToInstall = ["peft"]
                if !hasPreviousRuntime {
                    packagesToInstall = [
                        "torch", "torchvision",
                        "https://github.com/huggingface/diffusers/archive/\(Self.diffusersRevision).zip",
                        "transformers", "accelerate", "safetensors", "pillow", "sentencepiece", "peft"
                    ]
                }
                try await RuntimeCommand.run(uv, [
                    "pip", "install", "--python", python.path,
                    "--no-python-downloads", "--target", packages.path, "--upgrade"
                ] + (hasPreviousRuntime ? ["--no-deps"] : []) + packagesToInstall, environment: environment)

                state = .installing(String(localized: "runtime.install.check", defaultValue: "Vérification du GPU Apple…"))
                try await RuntimeCommand.run(
                    python,
                    [
                        "-c",
                        "import torch, diffusers, peft; from diffusers import QwenImage21Pipeline, QwenImage21Transformer2DModel, AutoencoderKLQwenImage21; assert torch.backends.mps.is_available(), 'MPS unavailable'"
                    ],
                    environment: environment
                )
                try Data("NanoApple runtime 4\nDiffusers \(Self.diffusersRevision)\n".utf8)
                    .write(to: Self.readyMarker(in: libraryRoot), options: .atomic)
                state = .ready
                await AppLog.shared.append(category: "Runtime", "Runtime prêt. Python embarqué, PyTorch, Diffusers et MPS ont été vérifiés.")
            } catch is CancellationError {
                state = .unavailable
                await AppLog.shared.append(.warning, category: "Runtime", "Installation annulée.")
            } catch {
                state = .failed(error.localizedDescription)
                await AppLog.shared.append(.error, category: "Runtime", error.localizedDescription)
            }
            task = nil
        }
    }

    func cancel() {
        task?.cancel()
    }

    nonisolated static func runtimeDirectory(in libraryRoot: URL) -> URL {
        libraryRoot.appending(path: "NanoAppleRuntime", directoryHint: .isDirectory)
    }

    nonisolated static func packagesDirectory(in libraryRoot: URL) -> URL {
        runtimeDirectory(in: libraryRoot).appending(path: "site-packages", directoryHint: .isDirectory)
    }

    nonisolated static func readyMarker(in libraryRoot: URL) -> URL {
        runtimeDirectory(in: libraryRoot).appending(path: ".ready-v4")
    }

    nonisolated static func bundledPythonURL() -> URL? {
        Bundle.main.url(forResource: "Python", withExtension: nil)?
            .appending(path: "bin/python3.12")
    }

    nonisolated static func isReady(in libraryRoot: URL) -> Bool {
        guard let python = bundledPythonURL() else { return false }
        return FileManager.default.isExecutableFile(atPath: python.path)
            && FileManager.default.fileExists(atPath: readyMarker(in: libraryRoot).path)
            && FileManager.default.fileExists(atPath: packagesDirectory(in: libraryRoot).appending(path: "torch", directoryHint: .isDirectory).path)
            && FileManager.default.fileExists(atPath: packagesDirectory(in: libraryRoot).appending(path: "peft", directoryHint: .isDirectory).path)
    }

    private func locateUV() -> URL? {
        let candidates = [
            Bundle.main.url(forResource: "uv", withExtension: nil),
            URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".local/bin/uv"),
            URL(fileURLWithPath: "/opt/homebrew/bin/uv"),
            URL(fileURLWithPath: "/usr/local/bin/uv")
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

private enum RuntimeCommand {
    static func run(_ executable: URL, _ arguments: [String], environment: [String: String] = [:]) async throws {
        try Task.checkCancellation()
        let command = ([executable.lastPathComponent] + arguments).joined(separator: " ")
        await AppLog.shared.append(category: "Runtime", "Commande : \(command)")

        do {
            let output = try await Task.detached(priority: .utility) { () throws -> String in
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

                let logURL = FileManager.default.temporaryDirectory
                    .appending(path: "nanoapple-runtime-\(UUID().uuidString).log")
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
                let log = try FileHandle(forWritingTo: logURL)
                defer {
                    try? log.close()
                    try? FileManager.default.removeItem(at: logURL)
                }
                process.standardOutput = log
                process.standardError = log
                try process.run()
                process.waitUntilExit()
                try log.synchronize()

                let data = (try? Data(contentsOf: logURL)) ?? Data()
                let message = String(decoding: data, as: UTF8.self)
                try Task.checkCancellation()
                guard process.terminationStatus == 0 else {
                    throw RuntimeCommandError.failed(
                        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Le processus d’installation a échoué (code \(process.terminationStatus))."
                            : message
                    )
                }
                return message
            }.value

            await AppLog.shared.append(category: "Runtime output", output)
        } catch {
            await AppLog.shared.append(.error, category: "Runtime command", error.localizedDescription)
            throw error
        }
    }
}

private enum RuntimeCommandError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): message
        }
    }
}
