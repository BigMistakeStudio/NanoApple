// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct FirstRunSetupView: View {
    private enum Step: Int, CaseIterable, Identifiable {
        case storage
        case runtime
        case qwen
        case safety
        case viggle

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .storage: L10n.Setup.storageStep
            case .runtime: L10n.Setup.runtimeStep
            case .qwen: L10n.Setup.qwenStep
            case .safety: L10n.Setup.safetyStep
            case .viggle: L10n.Setup.viggleStep
            }
        }
    }

    @EnvironmentObject private var storage: SecurityScopedStorage
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var modelLibrary: ModelLibrary
    @EnvironmentObject private var installer: ModelInstaller
    @EnvironmentObject private var runtime: RuntimeInstaller

    let onClose: () -> Void

    @State private var step: Step = .storage

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.Setup.title)
                    .font(.largeTitle.bold())
                Text(L10n.Setup.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(Step.allCases) { option in
                    HStack(spacing: 7) {
                        Image(systemName: option.rawValue < step.rawValue ? "checkmark.circle.fill" : "\(option.rawValue + 1).circle.fill")
                        Text(option.title)
                            .lineLimit(1)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(option == step ? Color.accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(option == step ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            ScrollView {
                Group {
                    switch step {
                    case .storage: storageStep
                    case .runtime: runtimeStep
                    case .qwen: modelSelectionStep
                    case .safety: safetyStep
                    case .viggle: packageStep(.viggleTurbo)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            Divider()
            HStack(spacing: 12) {
                Button(L10n.Setup.later) { onClose() }
                    .buttonStyle(.borderless)
                if installer.isBusy || runtime.state.isInstalling {
                    Text(L10n.Setup.backgroundInstall)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if step != .storage {
                    Button(L10n.Setup.back) {
                        step = Step(rawValue: step.rawValue - 1) ?? .storage
                    }
                }
                Button(isFinalStep ? L10n.Setup.finish : L10n.Setup.continueButton) {
                    if isFinalStep {
                        onClose()
                    } else {
                        step = Step(rawValue: step.rawValue + 1) ?? .viggle
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canContinue)
            }
        }
        .padding(26)
        .frame(width: 760, height: 550)
        .interactiveDismissDisabled()
        .onAppear {
            modelLibrary.refresh(in: storage.modelsURL)
            if !runtime.state.isInstalling { runtime.refresh(in: storage.modelsURL) }
            step = firstIncompleteStep
        }
        .onChange(of: storage.modelsURL) { _, root in
            modelLibrary.refresh(in: root)
            if !runtime.state.isInstalling { runtime.refresh(in: root) }
        }
    }

    private var canContinue: Bool {
        switch step {
        case .storage: storage.modelsURL != nil
        case .runtime: runtime.state == .ready
        case .qwen: modelLibrary.canGenerate(using: appModel.generationBackend) && appModel.generationBackend.advice.rating != .incompatible
        case .safety: !appModel.nsfwFilterEnabled || modelLibrary.state(for: .nsfwClassifier) == .ready
        case .viggle: true
        }
    }

    private var firstIncompleteStep: Step {
        if storage.modelsURL == nil { return .storage }
        if runtime.state != .ready { return .runtime }
        if !modelLibrary.canGenerate(using: appModel.generationBackend) { return .qwen }
        if appModel.nsfwFilterEnabled && modelLibrary.state(for: .nsfwClassifier) != .ready { return .safety }
        return appModel.generationBackend == .diffusers ? .viggle : .safety
    }

    private var isFinalStep: Bool {
        step == .viggle || (step == .safety && appModel.generationBackend != .diffusers)
    }

    private var modelSelectionStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            MacModelGuideView()
            Picker("Modèle à installer", selection: $appModel.generationBackend) {
                ForEach(GenerationBackend.allCases) { backend in
                    Text(backend.choiceTitle).tag(backend)
                }
            }
            ModelAdviceView(backend: appModel.generationBackend)
            ForEach(appModel.generationBackend.requiredPackages) { package in
                packageStep(package)
            }
        }
    }

    private var safetyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(L10n.Settings.nsfwFilter, isOn: $appModel.nsfwFilterEnabled)
            if appModel.nsfwFilterEnabled {
                packageStep(.nsfwClassifier)
            } else {
                Text(L10n.Setup.safetyDetail)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var storageStep: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(L10n.Setup.storageTitle, subtitle: L10n.Setup.storageDetail)
                Label(storage.modelsURL?.path(percentEncoded: false) ?? L10n.Models.none,
                      systemImage: "externaldrive.fill")
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let free = storage.availableSpace(at: storage.modelsURL) {
                    Text("\(free) \(L10n.Models.available)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let error = storage.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button(L10n.Setup.chooseFolder, systemImage: "folder") {
                    storage.choose(.models)
                }
                .buttonStyle(.borderedProminent)
                .disabled(installer.isBusy || runtime.state.isInstalling)
            }
        }
    }

    private var runtimeStep: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionHeading(L10n.Setup.runtimeTitle, subtitle: L10n.Setup.runtimeDetail)
                    Spacer()
                    StatusBadge(
                        title: runtimeBadgeTitle,
                        color: runtimeBadgeColor
                    )
                }

                switch runtime.state {
                case .installing(let message):
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        Text(message)
                    }
                    .font(.callout)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                case .ready:
                    Label(L10n.Setup.runtimeReadyDetail, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .unavailable:
                    EmptyView()
                }

                if runtime.state.isInstalling {
                    Button(L10n.Models.runtimeCancel, role: .cancel) { runtime.cancel() }
                } else if runtime.state != .ready {
                    Button(L10n.Setup.installRuntime, systemImage: "arrow.down.circle") {
                        guard let root = storage.modelsURL else { return }
                        runtime.install(in: root)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(storage.modelsURL == nil)
                }
            }
        }
    }

    private func packageStep(_ package: ModelPackage) -> some View {
        let state = installer.state(for: package)
        let ready = modelLibrary.state(for: package) == .ready
        return SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    SectionHeading(
                        package.name,
                        subtitle: package == .viggleTurbo ? L10n.Setup.viggleDetail
                            : (package == .nsfwClassifier ? L10n.Setup.safetyDetail : package.detail)
                    )
                    Spacer()
                    StatusBadge(title: packageBadgeTitle(for: state, ready: ready),
                                color: packageBadgeColor(for: state, ready: ready))
                }
                Text(package.approximateSize)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)

                ModelLicenseView(package: package)

                switch state {
                case .preparing:
                    ProgressView(L10n.Models.preparing)
                case .downloading(let progress, let file, let received, let total):
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress)
                        Text(file)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(format(received)) / \(format(total))")
                            .monospacedDigit()
                    }
                    .font(.caption)
                case .verifying(let progress, let file):
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress)
                        Text(L10n.Models.verifying)
                        Text(file).lineLimit(1).truncationMode(.middle)
                    }
                    .font(.caption)
                case .paused:
                    Label(L10n.Models.paused, systemImage: "pause.circle")
                        .foregroundStyle(.orange)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                case .idle, .installed:
                    EmptyView()
                }

                if state.isActive && installer.activePackageID == package.id {
                    Button(L10n.Models.cancel, role: .cancel) { installer.cancel() }
                } else if !ready {
                    Button(state == .paused || isFailed(state) ? L10n.Models.resume : L10n.Models.install,
                           systemImage: "arrow.down.circle") {
                        guard let root = storage.modelsURL else { return }
                        installer.install([package], in: root, modelLibrary: modelLibrary)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(storage.modelsURL == nil || installer.isBusy || appModel.generationBackend.advice.rating == .incompatible)
                }

                if package == .viggleTurbo {
                    Text(L10n.Setup.viggleOptional)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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

    private func packageBadgeTitle(for state: ModelInstaller.State, ready: Bool) -> String {
        if ready { return L10n.Models.ready }
        return switch state {
        case .preparing: L10n.Models.preparing
        case .downloading: L10n.Models.downloading
        case .verifying: L10n.Models.verifying
        case .paused: L10n.Models.paused
        case .failed: L10n.Models.failed
        case .idle, .installed: L10n.Models.notInstalled
        }
    }

    private func packageBadgeColor(for state: ModelInstaller.State, ready: Bool) -> Color {
        if ready { return .green }
        return switch state {
        case .preparing, .downloading, .verifying: .blue
        case .paused: .orange
        case .failed: .red
        case .idle, .installed: .secondary
        }
    }

    private func isFailed(_ state: ModelInstaller.State) -> Bool {
        if case .failed = state { return true }
        return false
    }
}
