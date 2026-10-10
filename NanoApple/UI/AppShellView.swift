// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct AppShellView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var storage: SecurityScopedStorage
    @EnvironmentObject private var modelLibrary: ModelLibrary
    @EnvironmentObject private var runtime: RuntimeInstaller

    var body: some View {
        NavigationSplitView {
            List(selection: $appModel.selection) {
                Section(L10n.Navigation.creationSection) {
                    item(.studio)
                    item(.characters)
                    item(.library)
                    item(.prompts)
                }

                Section(L10n.Navigation.configurationSection) {
                    item(.models)
                    item(.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
            .safeAreaInset(edge: .bottom) { engineStatus }
        } detail: {
            destination
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(appModel.selection?.title ?? L10n.App.name)
        .onAppear {
            modelLibrary.refresh(in: storage.modelsURL)
            if !runtime.state.isInstalling { runtime.refresh(in: storage.modelsURL) }
            appModel.offerSetupIfNeeded(
                modelReady: modelLibrary.canGenerate(using: appModel.generationBackend),
                runtimeReady: runtime.state == .ready,
                safetyReady: modelLibrary.state(for: .nsfwClassifier) == .ready
            )
        }
        .sheet(isPresented: $appModel.isShowingSetup) {
            FirstRunSetupView { appModel.dismissSetup() }
        }
        .onChange(of: appModel.selection) { _, destination in
            if destination == .studio || destination == .models {
                modelLibrary.refresh(in: storage.modelsURL)
            }
        }
    }

    private func item(_ destination: AppModel.Destination) -> some View {
        Label(destination.title, systemImage: destination.systemImage)
            .tag(destination)
    }

    @ViewBuilder
    private var destination: some View {
        switch appModel.selection ?? .studio {
        case .studio: StudioView()
        case .characters: CharacterLibraryView()
        case .library: CreationLibraryView()
        case .prompts: PromptLibraryView()
        case .models: ModelManagerView()
        case .settings: SettingsView()
        }
    }

    private var engineStatus: some View {
        let ready = modelLibrary.canGenerate(using: appModel.generationBackend)
        return HStack(spacing: 10) {
            Circle()
                .fill(ready ? .green : .orange)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(appModel.generationBackend.name)
                    .font(.caption.weight(.semibold))
                Text(ready ? L10n.Models.ready : L10n.Models.notInstalled)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.bar)
    }
}
