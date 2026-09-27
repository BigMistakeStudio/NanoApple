import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var storage: SecurityScopedStorage
    @EnvironmentObject private var modelLibrary: ModelLibrary

    var body: some View {
        Form {
            Section(L10n.Settings.appearance) {
                Picker(L10n.Settings.appearanceChoice, selection: $appModel.appearance) {
                    ForEach(AppModel.Appearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
            }

            Section(L10n.Settings.engine) {
                Picker(L10n.Settings.engineChoice, selection: $appModel.generationBackend) {
                    ForEach(GenerationBackend.allCases) { backend in
                        Text(backend.name).tag(backend)
                    }
                }
                LabeledContent(appModel.generationBackend.name) {
                    StatusBadge(
                        title: selectedModelIsReady ? L10n.Models.ready : L10n.Models.notInstalled,
                        color: selectedModelIsReady ? .green : .orange
                    )
                }
                Text(appModel.generationBackend.detail).foregroundStyle(.secondary)
            }

            Section(L10n.Settings.output) {
                LabeledContent(L10n.Settings.folder) {
                    Text(storage.generationOutputURL?.path(percentEncoded: false) ?? L10n.Settings.notSelected)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let error = storage.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                Button(L10n.Settings.chooseOutput) { storage.choose(.outputs) }
            }

            Section(L10n.Settings.privacy) {
                Label(L10n.Settings.privacyDetail, systemImage: "lock.shield")
            }

            Section(L10n.Settings.language) {
                Text(L10n.Settings.languageDetail).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 8)
    }

    private var selectedModelIsReady: Bool {
        modelLibrary.canGenerate(using: appModel.generationBackend)
    }
}
