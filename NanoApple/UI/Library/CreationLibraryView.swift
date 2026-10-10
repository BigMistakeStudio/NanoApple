// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

@MainActor
final class CreationLibraryViewModel: ObservableObject {
    struct Item: Identifiable {
        let url: URL
        let date: Date
        var id: URL { url }
    }

    @Published private(set) var items: [Item] = []

    func refresh(in directory: URL?, excluding excludedURLs: Set<URL> = []) {
        guard let directory else {
            items = []
            return
        }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []
        let extensions = Set(["png", "jpg", "jpeg", "heic", "webp"])
        items = urls.compactMap { url in
            guard extensions.contains(url.pathExtension.lowercased()),
                  !excludedURLs.contains(url.standardizedFileURL),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { return nil }
            return Item(url: url, date: values.contentModificationDate ?? .distantPast)
        }
        .sorted { $0.date > $1.date }
    }

    func permanentlyDelete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
        items.removeAll { $0.url == url }
    }
}

private enum CreationDeletion {
    case variant(projectID: UUID, variantID: UUID)
    case legacy(URL)
}

private struct ComparisonSelection: Hashable {
    let projectID: UUID
    let variantID: UUID
}

struct CreationLibraryView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var storage: SecurityScopedStorage
    @EnvironmentObject private var modelLibrary: ModelLibrary
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var generation: GenerationCoordinator
    @StateObject private var model = CreationLibraryViewModel()
    @State private var exportError: String?
    @State private var pendingDeletion: CreationDeletion?
    @State private var comparisonSelections: [ComparisonSelection] = []
    @State private var showingComparison = false
    @State private var revealedSafetyVariantIDs: Set<UUID> = []
    @State private var retryingSafetyVariantID: UUID?

    private static let safetyClassifier = NSFWClassifier()

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 310), spacing: 18)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(L10n.Library.title).font(.largeTitle.bold())
                Spacer()
                Button(L10n.Library.compare, systemImage: "rectangle.split.2x1") {
                    showingComparison = true
                }
                .disabled(comparisonItems.count != 2)
                .help(L10n.Library.compareHelp)
                Button(L10n.Library.refresh, systemImage: "arrow.clockwise") { refresh() }
                if let directory = storage.generationOutputURL {
                    Button(L10n.Library.openFolder, systemImage: "folder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory.path)
                    }
                }
            }

            if model.items.isEmpty && projectStore.projects.isEmpty {
                ContentUnavailableView {
                    Label(L10n.Library.emptyTitle, systemImage: "photo.stack")
                } description: {
                    Text(L10n.Library.emptyDescription)
                } actions: {
                    Button(L10n.Library.create) { appModel.selection = .studio }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if !projectStore.projects.allSatisfy({ $0.variants.isEmpty }) {
                            HStack {
                                Text(L10n.Library.compareHint)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if !comparisonSelections.isEmpty {
                                    Button(L10n.Library.clearComparison) {
                                        comparisonSelections.removeAll()
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        ForEach(projectStore.projects) { project in
                            projectSection(project)
                        }

                        if !model.items.isEmpty {
                            Text(L10n.Project.legacy)
                                .font(.title2.bold())
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                                ForEach(model.items) { item in
                                    creationCard(item)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(28)
        .onAppear {
            projectStore.configure(rootURL: storage.generationOutputURL)
            refresh()
        }
        .onChange(of: storage.outputsURL) { _, _ in refresh() }
        .sheet(isPresented: $showingComparison) {
            if comparisonItems.count == 2 {
                VariantComparisonView(
                    items: comparisonItems,
                    canRegenerate: !generation.state.isRunning,
                    onOpen: { selected in openComparisonItem(selected, regenerate: false) },
                    onRegenerate: { selected in openComparisonItem(selected, regenerate: true) }
                )
            }
        }
        .alert(L10n.Common.operationFailed, isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .confirmationDialog(
            L10n.Common.deletePermanently,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.Common.deletePermanently, role: .destructive) {
                confirmDeletion()
            }
            Button(L10n.Common.cancel, role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(L10n.Common.deleteConfirmation)
        }
    }

    private func projectSection(_ project: ImageProject) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name).font(.title2.bold())
                    Text("\(project.variants.count) \(L10n.Project.variants) · \(project.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.Project.open, systemImage: "arrow.right.circle") {
                    projectStore.activeProjectID = project.id
                    appModel.selection = .studio
                }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(project.variants.sorted(by: { $0.createdAt > $1.createdAt })) { variant in
                    variantCard(variant, project: project)
                }
            }
        }
    }

    private func variantCard(_ variant: ProjectVariant, project: ImageProject) -> some View {
        let url = projectStore.imageURL(for: variant, in: project)
        let selection = ComparisonSelection(projectID: project.id, variantID: variant.id)
        let comparisonIndex = comparisonSelections.firstIndex(of: selection)
        return SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Button {
                        projectStore.activeProjectID = project.id
                        projectStore.variantToOpenID = variant.id
                        appModel.selection = .studio
                    } label: {
                        Image(nsImage: NSImage(contentsOf: url) ?? NSImage())
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .clipped()
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    if appModel.nsfwFilterEnabled,
                       let assessment = variant.contentSafety,
                       assessment.needsCover,
                       !revealedSafetyVariantIDs.contains(variant.id) {
                        ContentSafetyCover(assessment: assessment) {
                            revealedSafetyVariantIDs.insert(variant.id)
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                if appModel.nsfwFilterEnabled && variant.contentSafety?.verdict == .unavailable {
                    Button(retryingSafetyVariantID == variant.id ? L10n.Safety.retrying : L10n.Safety.retry,
                           systemImage: "arrow.clockwise") {
                        retrySafetyAssessment(for: variant, in: project)
                    }
                    .disabled(retryingSafetyVariantID != nil)
                }

                Text(variant.kind.title)
                    .font(.callout.weight(.semibold))
                if let verdict = variant.evaluation?.verdict, verdict != .toReview {
                    Label(
                        verdict.title,
                        systemImage: verdict == .accepted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(verdict == .accepted ? Color.green : Color.orange)
                }
                if let width = variant.sourcePixelWidth, let height = variant.sourcePixelHeight {
                    Text("\(width) × \(height)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(variant.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    toggleComparison(selection)
                } label: {
                    Label(
                        comparisonIndex.map { $0 == 0 ? L10n.Library.comparisonA : L10n.Library.comparisonB }
                            ?? L10n.Library.selectForComparison,
                        systemImage: comparisonIndex == nil ? "square" : "checkmark.square.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help(comparisonIndex == nil ? L10n.Library.selectForComparison : L10n.Library.removeFromComparison)

                HStack {
                    Button { ImageExportService.reveal(url) } label: { Image(systemName: "folder") }
                        .help(L10n.Library.reveal)
                    Button(role: .destructive) {
                        pendingDeletion = .variant(projectID: project.id, variantID: variant.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help(L10n.Common.deletePermanently)
                    Spacer()
                    Button(L10n.Library.saveAs, systemImage: "square.and.arrow.down") { export(url) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func retrySafetyAssessment(for variant: ProjectVariant, in project: ImageProject) {
        guard retryingSafetyVariantID == nil else { return }
        guard let modelRoot = modelLibrary.installationURL(for: .nsfwClassifier),
              let libraryRoot = storage.modelsURL else {
            exportError = L10n.Studio.nsfwModelRequired
            return
        }
        let imageURL = projectStore.imageURL(for: variant, in: project)
        retryingSafetyVariantID = variant.id
        Task {
            do {
                let score = try await Self.safetyClassifier.classify(
                    imageURL: imageURL,
                    modelRoot: modelRoot,
                    runtimeModelRoot: libraryRoot,
                    outputDirectory: imageURL.deletingLastPathComponent()
                )
                try projectStore.saveContentSafety(
                    ContentSafetyAssessment(nsfwProbability: score),
                    for: variant.id,
                    in: project.id
                )
            } catch {
                exportError = error.localizedDescription
                await AppLog.shared.append(.error, category: "ContentSafety", error.localizedDescription)
            }
            retryingSafetyVariantID = nil
        }
    }

    private func creationCard(_ item: CreationLibraryViewModel.Item) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Button { ImageExportService.open(item.url) } label: {
                    Image(nsImage: NSImage(contentsOf: item.url) ?? NSImage())
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .clipped()
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Text(item.url.lastPathComponent)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        ImageExportService.reveal(item.url)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help(L10n.Library.reveal)
                    Button(role: .destructive) {
                        pendingDeletion = .legacy(item.url)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help(L10n.Common.deletePermanently)
                    Spacer()
                    Button(L10n.Library.saveAs, systemImage: "square.and.arrow.down") {
                        export(item.url)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func refresh() {
        let projectImages = Set(projectStore.projects.flatMap { project in
            project.variants.map { projectStore.imageURL(for: $0, in: project).standardizedFileURL }
        })
        model.refresh(in: storage.generationOutputURL, excluding: projectImages)
    }

    private var comparisonItems: [VariantComparisonItem] {
        comparisonSelections.compactMap { selection in
            guard let project = projectStore.projects.first(where: { $0.id == selection.projectID }),
                  let variant = project.variants.first(where: { $0.id == selection.variantID }) else {
                return nil
            }
            return VariantComparisonItem(
                project: project,
                variant: variant,
                imageURL: projectStore.imageURL(for: variant, in: project)
            )
        }
    }

    private func toggleComparison(_ selection: ComparisonSelection) {
        if let index = comparisonSelections.firstIndex(of: selection) {
            comparisonSelections.remove(at: index)
        } else if comparisonSelections.count < 2 {
            comparisonSelections.append(selection)
        } else {
            comparisonSelections[1] = selection
        }
    }

    private func openComparisonItem(_ item: VariantComparisonItem, regenerate: Bool) {
        guard !regenerate || !generation.state.isRunning else { return }
        projectStore.activeProjectID = item.project.id
        projectStore.variantToOpenID = item.variant.id
        projectStore.variantToRegenerateID = regenerate ? item.variant.id : nil
        appModel.promptToOpenID = nil
        showingComparison = false
        appModel.selection = .studio
    }

    private func export(_ url: URL) {
        do {
            try ImageExportService.saveCopy(of: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func confirmDeletion() {
        guard let deletion = pendingDeletion else { return }
        pendingDeletion = nil
        do {
            switch deletion {
            case .variant(let projectID, let variantID):
                try projectStore.permanentlyDeleteVariant(projectID: projectID, variantID: variantID)
                comparisonSelections.removeAll { $0.projectID == projectID && $0.variantID == variantID }
            case .legacy(let url):
                try model.permanentlyDelete(url)
            }
        } catch {
            exportError = error.localizedDescription
        }
    }
}
