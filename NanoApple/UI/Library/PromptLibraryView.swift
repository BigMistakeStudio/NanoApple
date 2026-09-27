import SwiftUI

struct PromptLibraryView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var storage: SecurityScopedStorage
    @EnvironmentObject private var projectStore: ProjectStore

    @State private var savedPromptToDelete: SavedPrompt?
    @State private var deletionError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.Studio.promptLibrary)
                        .font(.largeTitle.bold())
                    Text(L10n.Studio.promptLibrarySubtitle)
                        .foregroundStyle(.secondary)
                }

                SurfaceCard {
                    if projectStore.savedPrompts.isEmpty {
                        Label(L10n.Studio.promptLibraryEmpty, systemImage: "text.book.closed")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 110)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(projectStore.savedPrompts) { savedPrompt in
                                savedPromptRow(savedPrompt)
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), .clear, .purple.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .onAppear {
            projectStore.configure(rootURL: storage.generationOutputURL)
        }
        .alert(L10n.Common.operationFailed, isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("OK") { deletionError = nil }
        } message: {
            Text(deletionError ?? "")
        }
        .confirmationDialog(
            L10n.Studio.deleteSavedPrompt,
            isPresented: Binding(
                get: { savedPromptToDelete != nil },
                set: { if !$0 { savedPromptToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.Studio.deleteSavedPrompt, role: .destructive) {
                deletePendingSavedPrompt()
            }
            Button(L10n.Common.cancel, role: .cancel) { savedPromptToDelete = nil }
        } message: {
            Text(L10n.Studio.deleteSavedPromptConfirmation)
        }
    }

    private func savedPromptRow(_ savedPrompt: SavedPrompt) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                appModel.promptToOpenID = savedPrompt.id
                appModel.selection = .studio
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "text.quote")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 6) {
                        if !savedPrompt.prompt.isEmpty {
                            Text(savedPrompt.prompt)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(4)
                        }
                        if !savedPrompt.negativePrompt.isEmpty {
                            Text("\(L10n.Studio.negativePrompt) : \(savedPrompt.negativePrompt)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                        }
                        HStack(spacing: 12) {
                            Label(
                                savedPrompt.savedAt.formatted(date: .abbreviated, time: .shortened),
                                systemImage: "clock"
                            )
                            Label(L10n.Studio.useSavedPrompt, systemImage: "arrow.up.left")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .destructive) {
                savedPromptToDelete = savedPrompt
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(L10n.Studio.deleteSavedPrompt)
        }
        .padding(14)
        .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func deletePendingSavedPrompt() {
        guard let savedPrompt = savedPromptToDelete else { return }
        savedPromptToDelete = nil
        do {
            try projectStore.deleteSavedPrompt(id: savedPrompt.id)
        } catch {
            deletionError = error.localizedDescription
        }
    }
}
