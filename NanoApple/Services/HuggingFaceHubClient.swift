import CryptoKit
import Foundation

struct HubInstallProgress: Sendable {
    enum Phase: Sendable {
        case preparing
        case downloading
        case verifying
    }

    let phase: Phase
    let receivedBytes: Int64
    let totalBytes: Int64
    let currentFile: String
}

enum HubInstallationError: LocalizedError {
    case invalidRepository(String)
    case unsafePath(String)
    case insufficientSpace(required: Int64, available: Int64)
    case sizeMismatch(String)
    case checksumMismatch(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepository(let repository):
            return String(localized: "installer.error.repository", defaultValue: "Impossible de lire le dépôt \(repository).")
        case .unsafePath(let path):
            return String(localized: "installer.error.path", defaultValue: "Le dépôt contient un chemin non autorisé : \(path)")
        case .insufficientSpace(let required, let available):
            let needed = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            let free = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return String(localized: "installer.error.space", defaultValue: "Espace insuffisant : \(needed) requis, \(free) disponibles.")
        case .sizeMismatch(let file):
            return String(localized: "installer.error.size", defaultValue: "La taille du fichier \(file) ne correspond pas au dépôt.")
        case .checksumMismatch(let file):
            return String(localized: "installer.error.checksum", defaultValue: "La vérification SHA-256 a échoué pour \(file).")
        }
    }
}

actor HuggingFaceHubClient {
    typealias ProgressHandler = @Sendable (HubInstallProgress) async -> Void

    private struct ModelResponse: Decodable {
        struct Sibling: Decodable {
            struct LFS: Decodable {
                let sha256: String?
                let size: Int64?
            }

            let rfilename: String
            let size: Int64?
            let lfs: LFS?
        }

        let sha: String
        let siblings: [Sibling]
    }

    private struct RemoteFile: Sendable {
        let relativePath: String
        let size: Int64
        let sha256: String?
    }

    private struct RepositoryPlan: Sendable {
        let repository: HubRepository
        let revision: String
        let files: [RemoteFile]
    }

    func install(
        _ package: ModelPackage,
        in libraryRoot: URL,
        progress: @escaping ProgressHandler
    ) async throws -> ModelInstallationManifest {
        await progress(HubInstallProgress(phase: .preparing, receivedBytes: 0, totalBytes: package.approximateBytes, currentFile: ""))

        var plans: [RepositoryPlan] = []
        for repository in package.repositories {
            try Task.checkCancellation()
            plans.append(try await plan(for: repository))
        }

        let totalBytes = plans.flatMap(\.files).reduce(Int64(0)) { $0 + $1.size }
        let packageDirectory = package.directory(in: libraryRoot)
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
        try ensureEnoughSpace(for: plans, in: packageDirectory)

        var completedBytes: Int64 = 0
        var snapshots: [ModelInstallationManifest.RepositorySnapshot] = []

        for plan in plans {
            let repositoryDirectory = try safeDestination(
                for: plan.repository.destinationSubdirectory,
                inside: packageDirectory,
                directory: true
            )
            try FileManager.default.createDirectory(at: repositoryDirectory, withIntermediateDirectories: true)
            var manifestFiles: [ModelInstallationManifest.RepositorySnapshot.File] = []

            for remoteFile in plan.files {
                try Task.checkCancellation()
                let destination = try safeDestination(for: remoteFile.relativePath, inside: repositoryDirectory)
                let displayName = "\(plan.repository.id)/\(remoteFile.relativePath)"

                if try await isValidExistingFile(remoteFile, at: destination, completedBytes: completedBytes, totalBytes: totalBytes, displayName: displayName, progress: progress) {
                    completedBytes += remoteFile.size
                } else {
                    let partial = destination.appendingPathExtension("nanoapple.part")
                    if fileSize(at: partial) != remoteFile.size {
                        let source = try downloadURL(repositoryID: plan.repository.id, revision: plan.revision, filename: remoteFile.relativePath)
                        let baseBytes = completedBytes
                        let downloader = StreamingHTTPDownloader(
                            sourceURL: source,
                            partialURL: partial,
                            expectedBytes: remoteFile.size
                        ) { received, _ in
                            await progress(HubInstallProgress(
                                phase: .downloading,
                                receivedBytes: min(baseBytes + received, totalBytes),
                                totalBytes: totalBytes,
                                currentFile: displayName
                            ))
                        }
                        try await downloader.run()
                    }
                    try Task.checkCancellation()
                    try await validate(remoteFile, at: partial, completedBytes: completedBytes, totalBytes: totalBytes, displayName: displayName, progress: progress)

                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: partial, to: destination)
                    completedBytes += remoteFile.size
                }

                manifestFiles.append(.init(relativePath: remoteFile.relativePath, size: remoteFile.size, sha256: remoteFile.sha256))
            }

            snapshots.append(.init(
                repositoryID: plan.repository.id,
                revision: plan.revision,
                destinationSubdirectory: plan.repository.destinationSubdirectory,
                files: manifestFiles
            ))
        }

        let manifest = ModelInstallationManifest(
            formatVersion: 1,
            packageID: package.id,
            installedAt: Date(),
            repositories: snapshots
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: packageDirectory.appending(path: "manifest.json"), options: .atomic)
        return manifest
    }

    private func plan(for repository: HubRepository) async throws -> RepositoryPlan {
        guard let url = modelAPIURL(repositoryID: repository.id) else {
            throw HubInstallationError.invalidRepository(repository.id)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("NanoApple/0.1 (macOS; local model installer)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw HubInstallationError.invalidRepository(repository.id)
        }
        let model = try JSONDecoder().decode(ModelResponse.self, from: data)
        let availableFiles = model.siblings.map { sibling in
            RemoteFile(
                relativePath: sibling.rfilename,
                size: sibling.lfs?.size ?? sibling.size ?? 0,
                sha256: sibling.lfs?.sha256
            )
        }.filter { $0.size > 0 }
        let files: [RemoteFile]
        if let includedPaths = repository.includedPaths {
            let filesByPath = Dictionary(uniqueKeysWithValues: availableFiles.map { ($0.relativePath, $0) })
            files = includedPaths.compactMap { filesByPath[$0] }
            guard files.count == includedPaths.count else {
                throw HubInstallationError.invalidRepository(repository.id)
            }
        } else {
            files = availableFiles
        }
        guard !files.isEmpty else { throw HubInstallationError.invalidRepository(repository.id) }
        return RepositoryPlan(repository: repository, revision: model.sha, files: files)
    }

    private func isValidExistingFile(
        _ file: RemoteFile,
        at url: URL,
        completedBytes: Int64,
        totalBytes: Int64,
        displayName: String,
        progress: @escaping ProgressHandler
    ) async throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              fileSize(at: url) == file.size else { return false }
        guard let expectedChecksum = file.sha256 else { return true }

        await progress(HubInstallProgress(
            phase: .verifying,
            receivedBytes: completedBytes,
            totalBytes: totalBytes,
            currentFile: displayName
        ))
        let actual = try await checksum(of: url)
        return actual.caseInsensitiveCompare(expectedChecksum) == .orderedSame
    }

    private func validate(
        _ file: RemoteFile,
        at url: URL,
        completedBytes: Int64,
        totalBytes: Int64,
        displayName: String,
        progress: @escaping ProgressHandler
    ) async throws {
        guard fileSize(at: url) == file.size else {
            throw HubInstallationError.sizeMismatch(displayName)
        }
        guard let expectedChecksum = file.sha256 else { return }
        await progress(HubInstallProgress(
            phase: .verifying,
            receivedBytes: completedBytes + file.size,
            totalBytes: totalBytes,
            currentFile: displayName
        ))
        let actual = try await checksum(of: url)
        guard actual.caseInsensitiveCompare(expectedChecksum) == .orderedSame else {
            try? FileManager.default.removeItem(at: url)
            throw HubInstallationError.checksumMismatch(displayName)
        }
    }

    private func checksum(of url: URL) async throws -> String {
        let task = Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let data = try handle.read(upToCount: 4 * 1_024 * 1_024), !data.isEmpty {
                try Task.checkCancellation()
                hasher.update(data: data)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func ensureEnoughSpace(for plans: [RepositoryPlan], in directory: URL) throws {
        var missing: Int64 = 0
        var largestPossibleReplacement: Int64 = 0

        for plan in plans {
            let repositoryDirectory = try safeDestination(
                for: plan.repository.destinationSubdirectory,
                inside: directory,
                directory: true
            )
            for file in plan.files {
                let destination = try safeDestination(for: file.relativePath, inside: repositoryDirectory)
                if fileSize(at: destination) == file.size {
                    largestPossibleReplacement = max(largestPossibleReplacement, file.size)
                } else {
                    let partial = destination.appendingPathExtension("nanoapple.part")
                    missing += max(file.size - (fileSize(at: partial) ?? 0), 0)
                }
            }
        }

        let safetyMargin: Int64 = 2 * 1_024 * 1_024 * 1_024
        let required = missing + largestPossibleReplacement + safetyMargin
        let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage, available < required {
            throw HubInstallationError.insufficientSpace(required: required, available: available)
        }
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return nil }
        return size.int64Value
    }

    private func safeDestination(for relativePath: String, inside root: URL, directory: Bool = false) throws -> URL {
        guard !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..") else {
            throw HubInstallationError.unsafePath(relativePath)
        }
        let root = root.standardizedFileURL
        let candidate = root.appending(path: relativePath, directoryHint: directory ? .isDirectory : .notDirectory).standardizedFileURL
        let allowedPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path == root.path || candidate.path.hasPrefix(allowedPrefix) else {
            throw HubInstallationError.unsafePath(relativePath)
        }
        return candidate
    }

    private func modelAPIURL(repositoryID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.path = "/api/models/\(repositoryID)"
        components.queryItems = [URLQueryItem(name: "blobs", value: "true")]
        return components.url
    }

    private func downloadURL(repositoryID: String, revision: String, filename: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.path = "/\(repositoryID)/resolve/\(revision)/\(filename)"
        components.queryItems = [URLQueryItem(name: "download", value: "true")]
        guard let url = components.url else { throw HubInstallationError.invalidRepository(repositoryID) }
        return url
    }
}
