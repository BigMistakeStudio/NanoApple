// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation
import OSLog

@MainActor
final class SecurityScopedStorage: ObservableObject {
    enum Location: String, CaseIterable {
        case models
        case outputs
    }

    @Published private(set) var modelsURL: URL?
    @Published private(set) var outputsURL: URL?
    @Published private(set) var lastError: String?

    private var activeURLs: Set<URL> = []
    private let outputsMigrationKey = "NanoApple.storage.outputsPicturesMigration.v1"
    private let logger = Logger(subsystem: "ch.genevey.NanoApple", category: "Storage")

    var generationOutputURL: URL? {
        if let outputsURL { return outputsURL }
        return defaultOutputsURL
    }

    init() {
        modelsURL = restore(.models)
        let restoredOutputs = restore(.outputs)
        if isLegacyOutputsURL(restoredOutputs) {
            UserDefaults.standard.removeObject(forKey: key(for: .outputs))
            outputsURL = nil
        } else {
            outputsURL = restoredOutputs
        }
        if outputsURL == nil {
            prepareDefaultOutputsDirectory()
        }
    }

    deinit {
        for url in activeURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    func choose(_ location: Location) {
        let panel = NSOpenPanel()
        panel.title = location == .models ? L10n.Storage.chooseModels : L10n.Storage.chooseOutputs
        panel.prompt = L10n.Storage.choose
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        persist(url, for: location)
    }

    func availableSpace(at url: URL?) -> String? {
        guard let url,
              let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func prepareGenerationOutputDirectory() throws -> URL {
        if outputsURL == nil {
            prepareDefaultOutputsDirectory()
        }
        guard let url = generationOutputURL else {
            throw ImageGenerationError.externalStorageUnavailable
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func refreshDefaultOutputDirectory() {
        guard outputsURL == nil else { return }
        prepareDefaultOutputsDirectory()
    }

    private func persist(_ url: URL, for location: Location) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: key(for: location))
            beginAccessing(url)
            if location == .models { modelsURL = url } else { outputsURL = url }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func restore(_ location: Location) -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: key(for: location)) else { return nil }
        var isStale = false

        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            beginAccessing(url)
            if isStale { persist(url, for: location) }
            return url
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func beginAccessing(_ url: URL) {
        guard !activeURLs.contains(url), url.startAccessingSecurityScopedResource() else { return }
        activeURLs.insert(url)
    }

    private func key(for location: Location) -> String {
        "NanoApple.storage.\(location.rawValue).v1"
    }

    private var defaultOutputsURL: URL? {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?
            .appending(path: "NanoApple", directoryHint: .isDirectory)
    }

    private var legacyOutputsURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "NanoApple/Creations", directoryHint: .isDirectory)
    }

    private func isLegacyOutputsURL(_ url: URL?) -> Bool {
        guard let url, let legacyOutputsURL else { return false }
        return url.standardizedFileURL == legacyOutputsURL.standardizedFileURL
    }

    /// Copies creations made by older versions to ~/Pictures/NanoApple once.
    /// The old folder is intentionally retained so a failed migration cannot lose user data.
    private func prepareDefaultOutputsDirectory() {
        guard let destination = defaultOutputsURL else {
            lastError = String(localized: "storage.error.default_output", defaultValue: "Le dossier Images de l’utilisateur est introuvable.")
            logger.error("The user's Pictures directory could not be resolved.")
            return
        }

        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            migrateLegacyOutputsIfNeeded()
        } catch {
            lastError = String(
                localized: "storage.error.create_output",
                defaultValue: "Le dossier Images/NanoApple n’a pas pu être créé : \(error.localizedDescription)"
            )
            logger.error("Could not create \(destination.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func migrateLegacyOutputsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: outputsMigrationKey),
              let source = legacyOutputsURL,
              let destination = defaultOutputsURL,
              FileManager.default.fileExists(atPath: source.path) else { return }

        do {
            try mergeDirectory(at: source, into: destination)
            try rewriteLegacyPaths(in: destination, from: source)
            defaults.set(true, forKey: outputsMigrationKey)
            lastError = nil
            logger.notice("Migrated legacy creations to \(destination.path, privacy: .public)")
        } catch {
            lastError = String(
                localized: "storage.error.outputs_migration",
                defaultValue: "La migration des créations vers le dossier Images/NanoApple a échoué : \(error.localizedDescription)"
            )
            logger.error("Creation migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func mergeDirectory(at source: URL, into destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return }

        for case let sourceItem as URL in enumerator {
            let relativePath = sourceItem.path.replacingOccurrences(of: source.path + "/", with: "")
            let destinationItem = destination.appending(path: relativePath)
            let isDirectory = (try sourceItem.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                try fileManager.createDirectory(at: destinationItem, withIntermediateDirectories: true)
            } else if !fileManager.fileExists(atPath: destinationItem.path) {
                try fileManager.copyItem(at: sourceItem, to: destinationItem)
            }
        }
    }

    private func rewriteLegacyPaths(in destination: URL, from source: URL) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: destination,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let replacements = [
            (source.path, destination.path),
            (source.absoluteString, destination.absoluteString)
        ]
        for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "json" {
            guard var contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let original = contents
            for (oldPath, newPath) in replacements {
                contents = contents.replacingOccurrences(of: oldPath, with: newPath)
            }
            if contents != original {
                try contents.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }
}
