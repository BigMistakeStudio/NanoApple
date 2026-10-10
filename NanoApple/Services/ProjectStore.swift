// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation

@MainActor
final class ProjectStore: ObservableObject {
    enum StoreError: LocalizedError {
        case unavailable
        case projectNotFound
        case unmanagedFile
        case emptyPrompt

        var errorDescription: String? {
            switch self {
            case .unavailable:
                String(localized: "project.error.unavailable", defaultValue: "Le dossier des projets est indisponible.")
            case .projectNotFound:
                String(localized: "project.error.not_found", defaultValue: "Le projet actif est introuvable.")
            case .unmanagedFile:
                String(localized: "project.error.unmanaged_file", defaultValue: "NanoApple refuse de supprimer un fichier situé hors du projet actif.")
            case .emptyPrompt:
                String(localized: "prompt.error.empty", defaultValue: "Saisissez au moins un prompt avant de le sauvegarder.")
            }
        }
    }

    @Published private(set) var projects: [ImageProject] = []
    @Published private(set) var savedPrompts: [SavedPrompt] = []
    @Published private(set) var promptHistory: [PromptHistoryEntry] = []
    @Published var variantToOpenID: UUID?
    var variantToRegenerateID: UUID?
    @Published var activeProjectID: UUID? {
        didSet {
            UserDefaults.standard.set(activeProjectID?.uuidString, forKey: activeProjectKey)
        }
    }

    private var rootURL: URL?
    private let activeProjectKey = "NanoApple.activeProject.v1"

    init() {
        activeProjectID = UserDefaults.standard.string(forKey: activeProjectKey).flatMap(UUID.init(uuidString:))
    }

    var activeProject: ImageProject? {
        projects.first { $0.id == activeProjectID }
    }

    func configure(rootURL: URL?) {
        self.rootURL = rootURL
        reload()
        reloadPromptLibrary()
        reloadPromptHistory()
    }

    @discardableResult
    func createProject(named name: String? = nil) throws -> ImageProject {
        guard projectsRootURL != nil else { throw StoreError.unavailable }
        let project = ImageProject(name: name ?? suggestedProjectName())
        try createDirectories(for: project.id)
        projects.insert(project, at: 0)
        activeProjectID = project.id
        try persist(project)
        return project
    }

    @discardableResult
    func ensureActiveProject() throws -> ImageProject {
        if let activeProject { return activeProject }
        return try createProject()
    }

    func renameActiveProject(to proposedName: String) throws {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let activeProjectID,
              let index = projects.firstIndex(where: { $0.id == activeProjectID }) else {
            throw StoreError.projectNotFound
        }
        projects[index].name = name
        projects[index].updatedAt = Date()
        let updated = projects[index]
        sortProjects()
        try persist(updated)
    }

    func imagesDirectoryForActiveProject() throws -> URL {
        _ = try ensureActiveProject()
        return try outputImagesDirectory()
    }

    @discardableResult
    func addVariant(
        outputURL: URL,
        request: GenerationRequest,
        kind: ProjectVariant.Kind,
        parentID: UUID?,
        contentSafety: ContentSafetyAssessment? = nil
    ) throws -> ProjectVariant {
        let active = try ensureActiveProject()
        guard let index = projects.firstIndex(where: { $0.id == active.id }) else {
            throw StoreError.projectNotFound
        }

        let imagesDirectory = try outputImagesDirectory()
        let outputIsAlreadyInRoot = outputURL.deletingLastPathComponent().standardizedFileURL == imagesDirectory.standardizedFileURL
        let destination = outputIsAlreadyInRoot
            ? outputURL
            : imagesDirectory.appending(path: uniqueImageName(for: outputURL))
        if !outputIsAlreadyInRoot {
            try FileManager.default.copyItem(at: outputURL, to: destination)
        }

        let archivedRequest = try archiveResources(in: request, projectID: active.id)
        let size = NSImage(contentsOf: destination)?.representations.first.map {
            (width: $0.pixelsWide, height: $0.pixelsHigh)
        }
        let variant = ProjectVariant(
            kind: kind,
            parentID: parentID,
            relativeImagePath: destination.lastPathComponent,
            request: archivedRequest,
            sourcePixelWidth: size?.width,
            sourcePixelHeight: size?.height,
            contentSafety: contentSafety
        )
        projects[index].variants.append(variant)
        projects[index].draft = archivedRequest
        projects[index].updatedAt = Date()
        sortProjects()
        guard let updated = projects.first(where: { $0.id == active.id }) else {
            throw StoreError.projectNotFound
        }
        try persist(updated)
        return variant
    }

    func saveEvaluation(_ evaluation: ImageEvaluation, for variantID: UUID) throws {
        guard let projectIndex = projects.firstIndex(where: { $0.id == activeProjectID }),
              let variantIndex = projects[projectIndex].variants.firstIndex(where: { $0.id == variantID }) else {
            throw StoreError.projectNotFound
        }
        var updated = projects[projectIndex]
        updated.variants[variantIndex].evaluation = evaluation
        updated.updatedAt = Date()
        try persist(updated)
        projects[projectIndex] = updated
        sortProjects()
    }

    func saveContentSafety(_ assessment: ContentSafetyAssessment, for variantID: UUID, in projectID: UUID) throws {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }),
              let variantIndex = projects[projectIndex].variants.firstIndex(where: { $0.id == variantID }) else {
            throw StoreError.projectNotFound
        }
        var updated = projects[projectIndex]
        updated.variants[variantIndex].contentSafety = assessment
        try persist(updated)
        projects[projectIndex] = updated
    }

    @discardableResult
    func saveActiveProjectDraft(_ request: GenerationRequest) throws -> GenerationRequest {
        let active = try ensureActiveProject()
        guard let index = projects.firstIndex(where: { $0.id == active.id }) else {
            throw StoreError.projectNotFound
        }
        let archivedRequest = try archiveResources(in: request, projectID: active.id)
        projects[index].draft = archivedRequest
        try persist(projects[index])
        return archivedRequest
    }

    @discardableResult
    func savePrompt(prompt: String, negativePrompt: String) throws -> SavedPrompt {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNegativePrompt = negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty || !trimmedNegativePrompt.isEmpty else {
            throw StoreError.emptyPrompt
        }

        var updated = savedPrompts
        let savedPrompt: SavedPrompt
        if let existingIndex = updated.firstIndex(where: {
            $0.prompt == trimmedPrompt && $0.negativePrompt == trimmedNegativePrompt
        }) {
            var existing = updated.remove(at: existingIndex)
            existing.savedAt = Date()
            savedPrompt = existing
        } else {
            savedPrompt = SavedPrompt(prompt: trimmedPrompt, negativePrompt: trimmedNegativePrompt)
        }
        updated.insert(savedPrompt, at: 0)
        try persistPromptLibrary(updated)
        savedPrompts = updated
        return savedPrompt
    }

    func deleteSavedPrompt(id: UUID) throws {
        guard savedPrompts.contains(where: { $0.id == id }) else { return }
        let updated = savedPrompts.filter { $0.id != id }
        try persistPromptLibrary(updated)
        savedPrompts = updated
    }

    func recordPromptHistory(request: GenerationRequest, createdAt: Date, projectName: String) throws {
        guard !promptHistory.contains(where: { $0.id == request.id }) else { return }
        var updated = promptHistory
        updated.insert(PromptHistoryEntry(request: request, createdAt: createdAt, projectName: projectName), at: 0)
        try persistPromptHistory(updated)
        promptHistory = updated
    }

    func deletePromptHistoryEntry(id: UUID) throws {
        guard promptHistory.contains(where: { $0.id == id }) else { return }
        let updated = promptHistory.filter { $0.id != id }
        try persistPromptHistory(updated)
        promptHistory = updated
    }

    func clearPromptHistory() throws {
        guard !promptHistory.isEmpty else { return }
        try persistPromptHistory([])
        promptHistory = []
    }

    func permanentlyDeleteReference(_ url: URL) throws {
        guard let activeProjectID,
              let index = projects.firstIndex(where: { $0.id == activeProjectID }) else {
            throw StoreError.projectNotFound
        }
        let target = url.standardizedFileURL
        let assets = try assetsDirectory(for: activeProjectID).standardizedFileURL
        guard target.deletingLastPathComponent() == assets else {
            throw StoreError.unmanagedFile
        }

        let original = projects[index]
        var updated = original
        removeResource(target, from: &updated.draft)
        for variantIndex in updated.variants.indices {
            removeResource(target, from: &updated.variants[variantIndex].request)
        }
        updated.updatedAt = Date()
        try persist(updated)

        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
        } catch {
            try? persist(original)
            throw error
        }
        projects[index] = updated
        sortProjects()
    }

    func permanentlyDeleteVariant(projectID: UUID, variantID: UUID) throws {
        guard let index = projects.firstIndex(where: { $0.id == projectID }),
              let variantIndex = projects[index].variants.firstIndex(where: { $0.id == variantID }) else {
            throw StoreError.projectNotFound
        }
        let original = projects[index]
        let removed = original.variants[variantIndex]
        let target = imageURL(for: removed, in: original).standardizedFileURL
        let outputImages = try outputImagesDirectory().standardizedFileURL
        let legacyImages = legacyImagesDirectory(for: projectID).standardizedFileURL
        let parent = target.deletingLastPathComponent()
        guard parent == outputImages || parent == legacyImages else {
            throw StoreError.unmanagedFile
        }

        var updated = original
        updated.variants.remove(at: variantIndex)
        for childIndex in updated.variants.indices where updated.variants[childIndex].parentID == variantID {
            updated.variants[childIndex].parentID = nil
        }
        if updated.draft?.id == removed.request.id {
            updated.draft = updated.variants.max(by: { $0.createdAt < $1.createdAt })?.request
        }
        updated.updatedAt = Date()
        try persist(updated)

        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
        } catch {
            try? persist(original)
            throw error
        }
        projects[index] = updated
        if variantToOpenID == variantID { variantToOpenID = nil }
        sortProjects()
    }

    func imageURL(for variant: ProjectVariant, in project: ImageProject) -> URL {
        if variant.relativeImagePath.hasPrefix("Images/") {
            return projectDirectory(for: project.id).appending(path: variant.relativeImagePath)
        }
        return rootURL?.appending(path: variant.relativeImagePath)
            ?? projectDirectory(for: project.id).appending(path: variant.relativeImagePath)
    }

    func reload() {
        guard let projectsRootURL else {
            projects = []
            return
        }
        try? FileManager.default.createDirectory(at: projectsRootURL, withIntermediateDirectories: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let directories = (try? FileManager.default.contentsOfDirectory(
            at: projectsRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        projects = directories.compactMap { directory in
            let manifest = directory.appending(path: "project.json")
            guard let data = try? Data(contentsOf: manifest) else { return nil }
            guard let project = try? decoder.decode(ImageProject.self, from: data) else { return nil }
            return (try? migrateNestedImagesToRoot(in: project)) ?? project
        }
        sortProjects()
        if !projects.contains(where: { $0.id == activeProjectID }) {
            activeProjectID = projects.first?.id
        }
    }

    private func reloadPromptLibrary() {
        guard let promptLibraryURL,
              let data = try? Data(contentsOf: promptLibraryURL) else {
            savedPrompts = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        savedPrompts = ((try? decoder.decode([SavedPrompt].self, from: data)) ?? [])
            .sorted { $0.savedAt > $1.savedAt }
    }

    private func reloadPromptHistory() {
        guard let promptHistoryURL else {
            promptHistory = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: promptHistoryURL) {
            promptHistory = ((try? decoder.decode([PromptHistoryEntry].self, from: data)) ?? [])
                .sorted { $0.createdAt > $1.createdAt }
            return
        }
        guard !FileManager.default.fileExists(atPath: promptHistoryURL.path) else {
            promptHistory = []
            return
        }
        let entries = projects.flatMap { project in
            project.variants.compactMap { variant -> PromptHistoryEntry? in
                guard variant.kind == .generation || variant.kind == .variation else { return nil }
                return PromptHistoryEntry(
                    request: variant.request,
                    createdAt: variant.createdAt,
                    projectName: project.name
                )
            }
        }
        .sorted { $0.createdAt > $1.createdAt }
        promptHistory = entries
        try? persistPromptHistory(entries)
    }

    private var projectsRootURL: URL? {
        rootURL?.appending(path: "Projects", directoryHint: .isDirectory)
    }

    private var promptsDirectoryURL: URL? {
        rootURL?.appending(path: "Prompts", directoryHint: .isDirectory)
    }

    private var promptLibraryURL: URL? {
        promptsDirectoryURL?.appending(path: "library.json")
    }

    private var promptHistoryURL: URL? {
        promptsDirectoryURL?.appending(path: "history.json")
    }

    private func projectDirectory(for id: UUID) -> URL {
        projectsRootURL!.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    private func outputImagesDirectory() throws -> URL {
        guard let rootURL else { throw StoreError.unavailable }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func legacyImagesDirectory(for id: UUID) -> URL {
        projectDirectory(for: id).appending(path: "Images", directoryHint: .isDirectory)
    }

    private func assetsDirectory(for id: UUID) throws -> URL {
        try createDirectories(for: id)
        return projectDirectory(for: id).appending(path: "Assets", directoryHint: .isDirectory)
    }

    private func createDirectories(for id: UUID) throws {
        guard projectsRootURL != nil else { throw StoreError.unavailable }
        try FileManager.default.createDirectory(
            at: projectDirectory(for: id).appending(path: "Assets", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }

    private func migrateNestedImagesToRoot(in project: ImageProject) throws -> ImageProject {
        let fileManager = FileManager.default
        let outputDirectory = try outputImagesDirectory()
        var updated = project
        var migratedFiles: [(source: URL, destination: URL)] = []

        for index in updated.variants.indices {
            let relativePath = updated.variants[index].relativeImagePath
            guard relativePath.hasPrefix("Images/") else { continue }
            let source = projectDirectory(for: project.id).appending(path: relativePath)
            guard fileManager.fileExists(atPath: source.path) else { continue }

            let preferredDestination = outputDirectory.appending(path: source.lastPathComponent)
            let destination: URL
            if !fileManager.fileExists(atPath: preferredDestination.path) {
                try fileManager.copyItem(at: source, to: preferredDestination)
                destination = preferredDestination
            } else if fileManager.contentsEqual(atPath: source.path, andPath: preferredDestination.path) {
                destination = preferredDestination
            } else {
                destination = outputDirectory.appending(path: uniqueImageName(for: source))
                try fileManager.copyItem(at: source, to: destination)
            }

            updated.variants[index].relativeImagePath = destination.lastPathComponent
            migratedFiles.append((source, destination))
        }

        guard !migratedFiles.isEmpty else {
            try cleanupLegacyImagesDirectory(for: project.id)
            return updated
        }

        updated.updatedAt = Date()
        try persist(updated)
        for migrated in migratedFiles where fileManager.fileExists(atPath: migrated.source.path) {
            try fileManager.removeItem(at: migrated.source)
        }
        try cleanupLegacyImagesDirectory(for: project.id)
        return updated
    }

    private func cleanupLegacyImagesDirectory(for projectID: UUID) throws {
        let fileManager = FileManager.default
        let directory = legacyImagesDirectory(for: projectID)
        guard fileManager.fileExists(atPath: directory.path) else { return }

        let disposablePrefixes = [
            ".nanoapple-request-",
            ".nanoapple-status-",
            ".nanoapple-runtime-"
        ]
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        )
        for item in contents where item.lastPathComponent == ".DS_Store"
            || disposablePrefixes.contains(where: item.lastPathComponent.hasPrefix) {
            try fileManager.removeItem(at: item)
        }
        if try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty {
            try fileManager.removeItem(at: directory)
        }
    }

    private func archiveResources(in request: GenerationRequest, projectID: UUID) throws -> GenerationRequest {
        var archived = request
        archived.referenceImages = try request.referenceImages.map {
            try archive($0, in: projectID, prefix: "reference")
        }
        if let mask = request.maskImage {
            archived.maskImage = try archive(mask, in: projectID, prefix: "mask")
        }
        return archived
    }

    private func archive(_ source: URL, in projectID: UUID, prefix: String) throws -> URL {
        let directory = try assetsDirectory(for: projectID)
        if source.standardizedFileURL.deletingLastPathComponent() == directory.standardizedFileURL {
            return source.standardizedFileURL
        }
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
        let destination = directory.appending(path: "\(prefix)-\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private func removeResource(_ target: URL, from request: inout GenerationRequest) {
        let wasFirstReference = request.referenceImages.first?.standardizedFileURL == target
        request.referenceImages.removeAll { $0.standardizedFileURL == target }
        if wasFirstReference || request.maskImage?.standardizedFileURL == target {
            request.maskImage = nil
        }
    }

    private func removeResource(_ target: URL, from request: inout GenerationRequest?) {
        guard var value = request else { return }
        removeResource(target, from: &value)
        request = value
    }

    private func persist(_ project: ImageProject) throws {
        try createDirectories(for: project.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        try data.write(to: projectDirectory(for: project.id).appending(path: "project.json"), options: .atomic)
    }

    private func persistPromptLibrary(_ prompts: [SavedPrompt]) throws {
        guard let promptsDirectoryURL, let promptLibraryURL else {
            throw StoreError.unavailable
        }
        try FileManager.default.createDirectory(at: promptsDirectoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(prompts).write(to: promptLibraryURL, options: .atomic)
    }

    private func persistPromptHistory(_ entries: [PromptHistoryEntry]) throws {
        guard let promptsDirectoryURL, let promptHistoryURL else {
            throw StoreError.unavailable
        }
        try FileManager.default.createDirectory(at: promptsDirectoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(entries).write(to: promptHistoryURL, options: .atomic)
    }

    private func uniqueImageName(for source: URL) -> String {
        "\(source.deletingPathExtension().lastPathComponent)-\(UUID().uuidString.prefix(8)).\(source.pathExtension.isEmpty ? "png" : source.pathExtension)"
    }

    private func suggestedProjectName() -> String {
        let date = Date().formatted(date: .abbreviated, time: .shortened)
        return String(localized: "project.default_name", defaultValue: "Projet \(date)")
    }

    private func sortProjects() {
        projects.sort { $0.updatedAt > $1.updatedAt }
    }
}
