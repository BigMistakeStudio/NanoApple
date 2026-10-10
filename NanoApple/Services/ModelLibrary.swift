// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

@MainActor
final class ModelLibrary: ObservableObject {
    enum State: Equatable {
        case unavailable
        case missing
        case verifying
        case ready
        case failed(String)
    }

    @Published private(set) var states: [String: State] = [:]
    @Published private(set) var installationURLs: [String: URL] = [:]

    init() {
        for package in ModelPackage.supportedPackages {
            states[package.id] = .missing
        }
    }

    func state(for package: ModelPackage) -> State {
        states[package.id] ?? .unavailable
    }

    var canGenerate: Bool {
        state(for: .qwenImage21) == .ready
    }

    func canGenerate(using backend: GenerationBackend) -> Bool {
        backend.requiredPackages.allSatisfy { state(for: $0) == .ready }
    }

    func installationURL(for package: ModelPackage) -> URL? {
        installationURLs[package.id]
    }

    func refresh(in rootURL: URL?) {
        guard let rootURL else {
            for package in ModelPackage.supportedPackages {
                states[package.id] = .missing
            }
            installationURLs.removeAll()
            return
        }

        installationURLs.removeAll()
        for package in ModelPackage.supportedPackages {
            if let directory = installedDirectory(for: package, in: rootURL) {
                states[package.id] = .ready
                installationURLs[package.id] = directory
            } else {
                states[package.id] = .missing
            }
        }
    }

    private func installedDirectory(for package: ModelPackage, in rootURL: URL) -> URL? {
        packageDirectories(for: package, in: rootURL).first { verify(package, at: $0) }
    }

    /// Accepte la bibliothèque NanoApple, le dossier d'un paquet directement,
    /// ou la racine du SSD qui contient `NanoApple/`.
    private func packageDirectories(for package: ModelPackage, in rootURL: URL) -> [URL] {
        let root = rootURL.standardizedFileURL
        let candidates = [
            package.directory(in: root),
            root,
            root.appending(path: "NanoApple", directoryHint: .isDirectory)
                .appending(path: package.id, directoryHint: .isDirectory)
        ]

        return Array(Set(candidates.map(\.standardizedFileURL)))
    }

    private func verify(_ package: ModelPackage, at packageDirectory: URL) -> Bool {
        let manifestURL = packageDirectory.appending(path: "manifest.json")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? decoder.decode(ModelInstallationManifest.self, from: data),
              manifest.formatVersion == 1,
              manifest.packageID == package.id,
              Set(manifest.repositories.map(\.repositoryID)) == Set(package.repositories.map(\.id)) else {
            return false
        }

        return manifest.repositories.allSatisfy { repository in
            repository.files.allSatisfy { file in
                let url = packageDirectory
                    .appending(path: repository.destinationSubdirectory, directoryHint: .isDirectory)
                    .appending(path: file.relativePath)
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let fileSize = attributes[.size] as? NSNumber else { return false }
                return fileSize.int64Value == file.size
            }
        }
    }
}
