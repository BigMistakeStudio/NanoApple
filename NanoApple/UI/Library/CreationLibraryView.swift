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

struct CreationLibraryView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var storage: SecurityScopedStorage
    @EnvironmentObject private var projectStore: ProjectStore
    @StateObject private var model = CreationLibraryViewModel()
    @State private var exportError: String?
    @State private var pendingDeletion: CreationDeletion?

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 310), spacing: 18)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(L10n.Library.title).font(.largeTitle.bold())
                Spacer()
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
        return SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
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
            case .legacy(let url):
                try model.permanentlyDelete(url)
            }
        } catch {
            exportError = error.localizedDescription
        }
    }
}
