// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

@main
struct NanoAppleApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var storage = SecurityScopedStorage()
    @StateObject private var modelLibrary = ModelLibrary()
    @StateObject private var modelInstaller = ModelInstaller()
    @StateObject private var runtimeInstaller = RuntimeInstaller()
    @StateObject private var generation = GenerationCoordinator()
    @StateObject private var projectStore = ProjectStore()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environmentObject(appModel)
                .environmentObject(storage)
                .environmentObject(modelLibrary)
                .environmentObject(modelInstaller)
                .environmentObject(runtimeInstaller)
                .environmentObject(generation)
                .environmentObject(projectStore)
                .preferredColorScheme(appModel.appearance.colorScheme)
                .frame(minWidth: 1_080, minHeight: 720)
                .onAppear {
                    storage.refreshDefaultOutputDirectory()
                    modelLibrary.refresh(in: storage.modelsURL)
                    projectStore.configure(rootURL: storage.generationOutputURL)
                }
                .onChange(of: storage.modelsURL) { _, newValue in
                    modelLibrary.refresh(in: newValue)
                    if !runtimeInstaller.state.isInstalling { runtimeInstaller.refresh(in: newValue) }
                }
                .onChange(of: storage.outputsURL) { _, _ in
                    projectStore.configure(rootURL: storage.generationOutputURL)
                }
                .onChange(of: appModel.generationBackend) { _, backend in
                    Task { await generation.switchBackend(to: backend) }
                }
        }
        .defaultSize(width: 1_300, height: 840)
        .commands { ToolsCommands() }

        Window(L10n.Logs.title, id: "logs") {
            LogsView()
        }
        .defaultSize(width: 900, height: 620)

        Settings {
            SettingsView()
                .environmentObject(appModel)
                .environmentObject(storage)
                .environmentObject(modelLibrary)
                .environmentObject(modelInstaller)
                .environmentObject(runtimeInstaller)
                .environmentObject(generation)
                .preferredColorScheme(appModel.appearance.colorScheme)
                .frame(width: 640, height: 500)
        }
    }
}
