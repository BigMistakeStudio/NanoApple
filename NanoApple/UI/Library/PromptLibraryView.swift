// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

private enum PromptDeletion {
    case saved(UUID)
    case history(UUID)
    case allHistory
}

struct PromptLibraryView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var storage: SecurityScopedStorage
    @EnvironmentObject private var projectStore: ProjectStore

    @State private var pendingDeletion: PromptDeletion?
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

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SectionHeading(L10n.Studio.promptHistory)
                            Spacer()
                            Button(L10n.Studio.clearPromptHistory, systemImage: "trash", role: .destructive) {
                                pendingDeletion = .allHistory
                            }
                            .disabled(projectStore.promptHistory.isEmpty)
                        }
                        if projectStore.promptHistory.isEmpty {
                            Label(L10n.Studio.promptHistoryEmpty, systemImage: "clock.arrow.circlepath")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 90)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(projectStore.promptHistory) { entry in
                                    historyRow(entry)
                                }
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
            deletionTitle,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(deletionTitle, role: .destructive) {
                deletePendingPrompt()
            }
            Button(L10n.Common.cancel, role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(deletionMessage)
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
                pendingDeletion = .saved(savedPrompt.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(L10n.Studio.deleteSavedPrompt)
        }
        .padding(14)
        .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func historyRow(_ entry: PromptHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.projectName)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    pendingDeletion = .history(entry.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(L10n.Studio.deletePromptHistory)
            }
            Text(L10n.Studio.originalPrompt)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(entry.originalPrompt)
                .font(.callout)
                .lineLimit(3)
                .textSelection(.enabled)
            if let enhanced = entry.enhancedPrompt, !enhanced.isEmpty {
                Text(L10n.Studio.enhancedPrompt)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(enhanced)
                    .font(.callout)
                    .lineLimit(4)
                    .textSelection(.enabled)
            } else if entry.usedPrompt != entry.originalPrompt {
                Text(L10n.Studio.finalPrompt)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(entry.usedPrompt)
                    .font(.callout)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
            HStack {
                Button(L10n.Studio.useOriginalPrompt, systemImage: "arrow.up.left") {
                    openHistoryEntry(entry, useOriginal: true)
                }
                if entry.usedPrompt != entry.originalPrompt {
                    Button(L10n.Studio.useFinalPrompt, systemImage: "arrow.up.left.square") {
                        openHistoryEntry(entry, useOriginal: false)
                    }
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func openHistoryEntry(_ entry: PromptHistoryEntry, useOriginal: Bool) {
        appModel.promptHistoryToOpen = .init(id: entry.id, useOriginal: useOriginal)
        appModel.selection = .studio
    }

    private var deletionTitle: String {
        switch pendingDeletion {
        case .saved: L10n.Studio.deleteSavedPrompt
        case .history: L10n.Studio.deletePromptHistory
        case .allHistory: L10n.Studio.clearPromptHistory
        case nil: L10n.Studio.deletePromptHistory
        }
    }

    private var deletionMessage: String {
        switch pendingDeletion {
        case .saved: L10n.Studio.deleteSavedPromptConfirmation
        case .history: L10n.Studio.deletePromptHistoryConfirmation
        case .allHistory: L10n.Studio.clearPromptHistoryConfirmation
        case nil: ""
        }
    }

    private func deletePendingPrompt() {
        guard let deletion = pendingDeletion else { return }
        pendingDeletion = nil
        do {
            switch deletion {
            case .saved(let id): try projectStore.deleteSavedPrompt(id: id)
            case .history(let id): try projectStore.deletePromptHistoryEntry(id: id)
            case .allHistory: try projectStore.clearPromptHistory()
            }
        } catch {
            deletionError = error.localizedDescription
        }
    }
}
