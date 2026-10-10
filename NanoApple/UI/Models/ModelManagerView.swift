// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct ModelManagerView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var storage: SecurityScopedStorage
    @EnvironmentObject private var modelLibrary: ModelLibrary
    @EnvironmentObject private var installer: ModelInstaller
    @EnvironmentObject private var runtime: RuntimeInstaller

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.Models.title).font(.largeTitle.bold())
                        Text(L10n.Models.subtitle).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.Setup.reopen, systemImage: "list.number") {
                        appModel.isShowingSetup = true
                    }
                    .buttonStyle(.bordered)
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 14) {
                        MacModelGuideView()
                        Button("Choisir le Turbo conseillé pour ce Mac") {
                            appModel.generationBackend = ModelAdvice.preferredTurbo()
                        }
                        .disabled(installer.isBusy || ModelAdvice.assess(ModelAdvice.preferredTurbo()).rating == .incompatible)
                    }
                }
                storageCard
                runtimeCard
                completeInstallationCard

                ForEach(ModelPackage.supportedPackages) { package in
                    packageCard(package)
                }
            }
            .padding(28)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            modelLibrary.refresh(in: storage.modelsURL)
            runtime.refresh(in: storage.modelsURL)
        }
    }

    private var storageCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(L10n.Models.storageTitle, subtitle: L10n.Models.storageSubtitle)
                HStack(spacing: 14) {
                    Image(systemName: "externaldrive.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(storage.modelsURL?.path(percentEncoded: false) ?? L10n.Models.none)
                            .lineLimit(1)
                        if let free = storage.availableSpace(at: storage.modelsURL) {
                            Text("\(free) \(L10n.Models.available)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(L10n.Models.choose) { storage.choose(.models) }
                        .disabled(installer.isBusy)
                }
            }
        }
    }

    private var completeInstallationCard: some View {
        SurfaceCard {
            HStack(spacing: 16) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Installer le modèle choisi").font(.headline)
                    Text(String(localized: "models.selected.summary", defaultValue: "\(appModel.generationBackend.name) · \(appModel.generationBackend.modelPackage.approximateSize) pour le modèle"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(L10n.Models.sequentialNote)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Installer le modèle choisi") {
                    guard let root = storage.modelsURL else { return }
                    installer.install(appModel.generationBackend.requiredPackages + (appModel.nsfwFilterEnabled ? [.nsfwClassifier] : []), in: root, modelLibrary: modelLibrary)
                }
                .buttonStyle(.borderedProminent)
                .disabled(storage.modelsURL == nil || installer.isBusy || appModel.generationBackend.advice.rating == .incompatible)
            }
        }
    }

    private var runtimeCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    Image(systemName: "cpu.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Models.runtimeTitle).font(.headline)
                        Text(L10n.Models.runtimeDetail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(title: runtimeBadgeTitle, color: runtimeBadgeColor)
                }

                runtimeDetails

                HStack {
                    Button(L10n.Logs.show, systemImage: "doc.text.magnifyingglass") {
                        openWindow(id: "logs")
                    }
                    Spacer()
                    if runtime.state.isInstalling {
                        Button(L10n.Models.runtimeCancel, role: .cancel) { runtime.cancel() }
                    } else {
                        Button(L10n.Models.runtimeInstall) {
                            guard let root = storage.modelsURL else { return }
                            runtime.install(in: root)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(storage.modelsURL == nil)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var runtimeDetails: some View {
        switch runtime.state {
        case .installing(let message):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(message)
            }
            .font(.caption)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        case .ready, .unavailable:
            EmptyView()
        }
    }

    private var runtimeBadgeTitle: String {
        switch runtime.state {
        case .ready: L10n.Models.runtimeReady
        case .installing: L10n.Models.preparing
        case .failed: L10n.Models.failed
        case .unavailable: L10n.Models.runtimeMissing
        }
    }

    private var runtimeBadgeColor: Color {
        switch runtime.state {
        case .ready: .green
        case .installing: .blue
        case .failed: .red
        case .unavailable: .orange
        }
    }

    private func packageCard(_ package: ModelPackage) -> some View {
        let installState = installer.state(for: package)
        let isReady = modelLibrary.state(for: package) == .ready || installState == .installed
        let backend = GenerationBackend.allCases.first { $0.modelPackage == package }

        return SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    Image(systemName: "shippingbox.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(package.name).font(.headline)
                            Text(package == appModel.generationBackend.modelPackage ? String(localized: "models.selected.badge", defaultValue: "Modèle choisi") : L10n.Models.optional)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(package.detail).font(.callout).foregroundStyle(.secondary)
                        repositories(for: package)
                    }
                    Spacer()
                    Text(package.approximateSize)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    StatusBadge(title: badgeTitle(for: installState, ready: isReady), color: badgeColor(for: installState, ready: isReady))
                }

                if let backend {
                    ModelAdviceView(backend: backend)
                    if backend.isTurbo {
                        HStack {
                            Text("Taille totale du paquet : \(package.approximateSize)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if appModel.generationBackend != backend {
                                Button("Choisir ce modèle") { appModel.generationBackend = backend }
                                    .disabled(installer.isBusy || backend.advice.rating == .incompatible)
                            }
                        }
                    }
                }
                ModelLicenseView(package: package)
                installationDetails(installState)

                HStack {
                    if storage.modelsURL == nil {
                        Label(L10n.Models.chooseStorageFirst, systemImage: "externaldrive.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    if installState.isActive && installer.activePackageID == package.id {
                        Button(L10n.Models.cancel, role: .cancel) { installer.cancel() }
                    } else {
                        Button(buttonTitle(for: installState, ready: isReady)) {
                            guard let root = storage.modelsURL else { return }
                            installer.install([package], in: root, modelLibrary: modelLibrary)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(storage.modelsURL == nil || installer.isBusy || backend?.advice.rating == .incompatible)
                    }
                }
            }
        }
    }

    private func repositories(for package: ModelPackage) -> some View {
        HStack(spacing: 6) {
            Text(L10n.Models.source + ":")
            ForEach(Array(package.repositories.enumerated()), id: \.element.id) { index, repository in
                if index > 0 { Text("·") }
                Link(repository.id, destination: URL(string: "https://huggingface.co/\(repository.id)")!)
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func installationDetails(_ state: ModelInstaller.State) -> some View {
        switch state {
        case .preparing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.Models.preparing)
            }
            .font(.caption)
        case .downloading(let progress, let file, let received, let total):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress)
                HStack {
                    Text(file).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text("\(format(received)) / \(format(total))")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        case .verifying(let progress, let file):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress)
                Label(L10n.Models.verifying, systemImage: "checkmark.shield")
                    .font(.caption)
                Text(file)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .paused:
            Label(L10n.Models.paused, systemImage: "pause.circle")
                .font(.caption)
                .foregroundStyle(.orange)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 3) {
                Label(L10n.Models.failed, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        case .idle, .installed:
            EmptyView()
        }
    }

    private func badgeTitle(for state: ModelInstaller.State, ready: Bool) -> String {
        switch state {
        case .preparing: L10n.Models.preparing
        case .downloading: L10n.Models.downloading
        case .verifying: L10n.Models.verifying
        case .paused: L10n.Models.paused
        case .failed: L10n.Models.failed
        case .installed: L10n.Models.ready
        case .idle: ready ? L10n.Models.ready : L10n.Models.notInstalled
        }
    }

    private func badgeColor(for state: ModelInstaller.State, ready: Bool) -> Color {
        switch state {
        case .installed: .green
        case .failed: .red
        case .preparing, .downloading, .verifying: .blue
        case .paused: .orange
        case .idle: ready ? .green : .secondary
        }
    }

    private func buttonTitle(for state: ModelInstaller.State, ready: Bool) -> String {
        switch state {
        case .paused, .failed: L10n.Models.resume
        default: ready ? L10n.Models.repair : L10n.Models.install
        }
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
