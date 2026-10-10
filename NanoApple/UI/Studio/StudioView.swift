// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct StudioView: View {
    private enum SimpleImageFormat: CaseIterable, Identifiable {
        case square, landscape, portrait, socialPortrait, ultrawide

        var id: Self { self }

        var title: String {
            switch self {
            case .square: "1:1"
            case .landscape: "16:9"
            case .portrait: "9:16"
            case .socialPortrait: "4:5"
            case .ultrawide: "16:7"
            }
        }

        var aspectRatio: Double {
            switch self {
            case .square: 1
            case .landscape: 16.0 / 9
            case .portrait: 9.0 / 16
            case .socialPortrait: 4.0 / 5
            case .ultrawide: 16.0 / 7
            }
        }
    }

    private enum SimpleImageSize: CaseIterable, Identifiable {
        case standard, large

        var id: Self { self }

        var title: String {
            switch self {
            case .standard: L10n.Studio.standardSize
            case .large: L10n.Studio.largeSize
            }
        }
    }

    private struct PromptPreviewSource: Equatable {
        let prompt: String
        let mode: GenerationMode
        let preset: GenerationPreset
        let references: [URL]
        let backend: GenerationBackend
    }

    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var storage: SecurityScopedStorage
    @EnvironmentObject private var modelLibrary: ModelLibrary
    @EnvironmentObject private var generation: GenerationCoordinator
    @EnvironmentObject private var projectStore: ProjectStore

    @AppStorage("NanoApple.studio.expertMode.v1") private var isExpertMode = false
    @State private var mode: GenerationMode = .create
    @State private var preset: GenerationPreset = .none
    @State private var prompt = L10n.Studio.defaultPrompt
    @State private var negativePrompt = ""
    @State private var referenceURLs: [URL] = []
    @State private var resolution: CanvasResolution = .square
    @State private var simpleImageFormat: SimpleImageFormat = .square
    @State private var simpleImageSize: SimpleImageSize = .standard
    @State private var customWidth = 1_024
    @State private var customHeight = 1_024
    @State private var steps = 30.0
    @State private var seed = 42
    @State private var randomizeSeed = true
    @State private var enhancePrompt = false
    @State private var useViggleTurbo = false
    @State private var useConsistencyLoRA = false
    @State private var orbitSettings = ViewpointOrbitSettings()
    @State private var showViggleHelp = false
    @State private var showConsistencyHelp = false
    @State private var showAdvanced = false
    @State private var exportError: String?
    @State private var maskURL: URL?
    @State private var showMaskEditor = false
    @State private var previewOverrideURL: URL?
    @State private var revealedSafetyPreviewURL: URL?
    @State private var isRetryingSafety = false
    @State private var retriedSafetyVariantIDs: Set<UUID> = []
    @State private var previewRequest: GenerationRequest?
    @State private var currentVariantID: UUID?
    @State private var pendingVariantKind: ProjectVariant.Kind = .generation
    @State private var pendingParentVariantID: UUID?
    @State private var lastPersistedOutputURL: URL?
    @State private var isUpscaling = false
    @State private var referenceToDelete: URL?
    @State private var loadedProjectID: UUID?
    @State private var promptsWereSaved = false
    @State private var variantPromptWasSaved = false
    @State private var keepStartupPreviewEmpty = false
    @State private var showPromptGuide = false
    @State private var evaluation = ImageEvaluation()
    @State private var previewHasTransparentPixels: Bool?
    @FocusState private var promptEditorFocused: Bool
    @State private var preparedPrompt = ""
    @State private var preparedPromptSource: PromptPreviewSource?
    @State private var usePreparedPrompt = true
    @State private var isPreparingPrompt = false
    @State private var promptPreparationTask: Task<Void, Never>?
    @State private var promptPreparationID: UUID?
    @State private var finalParentVariantID: UUID?

    private static let upscaler = ImageUpscaler()
    private static let safetyClassifier = NSFWClassifier()

    private var studioContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if isExpertMode {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 18) {
                            modeCard
                            if mode.acceptsReferences { referencesCard }
                            if mode == .viewpointOrbit {
                                orbitCard
                            } else {
                                promptCard
                                if enhancePrompt || displayedPromptResult != nil {
                                    promptResultCard
                                }
                                presetCard
                            }
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 18) {
                            previewCard
                            settingsCard
                        }
                        .frame(width: 330)
                    }
                } else {
                    simpleStudio
                }
            }
            .padding(28)
            .frame(maxWidth: 1_280)
            .frame(maxWidth: .infinity)
        }
        .background {
            if isExpertMode {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.10), .clear, .purple.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            } else {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
            }
        }
    }

    var body: some View {
        studioContent
        .onChange(of: appModel.generationBackend) { _, _ in
            refreshModelAvailability()
        }
        .onAppear {
            refreshModelAvailability()
            projectStore.configure(rootURL: storage.generationOutputURL)
            keepStartupPreviewEmpty = !appModel.didInitializeStudioPrompts
                && projectStore.variantToOpenID == nil
            appModel.didInitializeStudioPrompts = true
            loadedProjectID = projectStore.activeProjectID
            loadActiveProject(restorePrompts: !keepStartupPreviewEmpty)
            openRequestedPrompt()
            if let variantID = projectStore.variantToRegenerateID {
                projectStore.variantToRegenerateID = nil
                if currentVariantID == variantID && !generation.state.isRunning {
                    let backend = previewRequest?.backend ?? appModel.generationBackend
                    Task {
                        await generation.switchBackend(to: backend)
                        guard appModel.selection == .studio,
                              currentVariantID == variantID else { return }
                        appModel.generationBackend = backend
                        isExpertMode = true
                        startGeneration(kind: .variation, parentID: variantID)
                    }
                }
            }
        }
        .onChange(of: projectStore.activeProjectID) { _, newValue in
            guard newValue != loadedProjectID else { return }
            finalParentVariantID = nil
            loadedProjectID = newValue
            loadActiveProject(restorePrompts: !keepStartupPreviewEmpty)
        }
        .onChange(of: prompt) { _, _ in promptsWereSaved = false }
        .onChange(of: preparedPrompt) { _, _ in variantPromptWasSaved = false }
        .onChange(of: promptPreviewSource) { _, _ in
            promptPreparationTask?.cancel()
            promptPreparationID = nil
            isPreparingPrompt = false
        }
        .onChange(of: negativePrompt) { _, _ in promptsWereSaved = false }
        .onChange(of: useViggleTurbo) { _, _ in persistWorkspaceDraft() }
        .onChange(of: orbitSettings) { _, _ in
            if mode == .viewpointOrbit { persistWorkspaceDraft() }
        }
        .onChange(of: appModel.promptToOpenID) { _, _ in openRequestedPrompt() }
        .onChange(of: appModel.promptHistoryToOpen) { _, _ in openRequestedPrompt() }
        .onChange(of: generation.state) { _, state in
            if case .completed(let url) = state { persistCompletedGeneration(url) }
        }
        .onDisappear {
            promptPreparationTask?.cancel()
            promptPreparationID = nil
            promptPreparationTask = nil
            isPreparingPrompt = false
        }
        .sheet(isPresented: $showMaskEditor) {
            if let source = referenceURLs.first {
                MaskEditorView(sourceURL: source) {
                    maskURL = $0
                    persistWorkspaceDraft()
                }
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
                get: { referenceToDelete != nil },
                set: { if !$0 { referenceToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.Common.deletePermanently, role: .destructive) {
                deletePendingReference()
            }
            Button(L10n.Common.cancel, role: .cancel) { referenceToDelete = nil }
        } message: {
            Text(L10n.Common.deleteConfirmation)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.Studio.title)
                    .font(.largeTitle.bold())
                if isExpertMode {
                    Text(L10n.Studio.subtitle)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isExpertMode {
                Picker(L10n.Project.title, selection: validProjectSelection) {
                    if projectStore.projects.isEmpty {
                        Text(L10n.Project.new).tag(nil as UUID?)
                    }
                    ForEach(projectStore.projects) { project in
                        Text(project.name).tag(project.id as UUID?)
                    }
                }
                .frame(width: 230)
                Button {
                    renameActiveProject()
                } label: {
                    Image(systemName: "pencil")
                }
                .help(L10n.Project.rename)
                .disabled(projectStore.activeProject == nil)
                Button {
                    do {
                        _ = try projectStore.createProject()
                        clearWorkspace()
                    } catch {
                        exportError = error.localizedDescription
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help(L10n.Project.new)
            }
            Button {
                toggleInterfaceMode()
            } label: {
                Label(
                    isExpertMode ? L10n.Studio.simpleMode : L10n.Studio.expertMode,
                    systemImage: isExpertMode ? "rectangle.compress.vertical" : "slider.horizontal.3"
                )
            }
            .buttonStyle(.bordered)
        }
    }

    private func toggleInterfaceMode() {
        if isExpertMode {
            promptPreparationTask?.cancel()
            promptPreparationID = nil
            promptPreparationTask = nil
            isPreparingPrompt = false
            syncSimpleCanvasSelection()
        }
        isExpertMode.toggle()
    }

    private var simpleStudio: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.Studio.prompt)
                    .font(.headline)
                TextEditor(text: $prompt)
                    .font(.body)
                    .focused($promptEditorFocused)
                    .scrollContentBackground(.hidden)
                    .padding(14)
                    .frame(height: 170)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                promptEditorFocused ? Color.accentColor : Color.primary.opacity(0.32),
                                lineWidth: promptEditorFocused ? 2 : 1
                            )
                    }
                    .overlay(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text(L10n.Studio.promptPlaceholder)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 19)
                                .padding(.vertical, 22)
                                .allowsHitTesting(false)
                        }
                    }
            }

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Studio.engine).font(.headline)
                    Picker(L10n.Studio.engine, selection: $appModel.generationBackend) {
                        ForEach(GenerationBackend.allCases) { backend in
                            Text(backend.choiceTitle).tag(backend)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    ModelAdviceView(backend: appModel.generationBackend,
                                    width: simpleCanvas.width, height: simpleCanvas.height)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Studio.preset).font(.headline)
                    Picker(L10n.Studio.preset, selection: presetSelection) {
                        ForEach(GenerationPreset.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Studio.format).font(.headline)
                    Picker(L10n.Studio.format, selection: simpleFormatSelection) {
                        ForEach(SimpleImageFormat.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Studio.size).font(.headline)
                    Picker(L10n.Studio.size, selection: simpleSizeSelection) {
                        ForEach(SimpleImageSize.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }

            Text("\(simpleCanvas.width) × \(simpleCanvas.height) px")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !selectedModelIsReady {
                Label(simpleModelWarning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if simpleImageSize == .large {
                Label(L10n.Studio.highResolutionWarning, systemImage: "memorychip")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button {
                startGeneration()
            } label: {
                Label(
                    selectedModelIsReady ? L10n.Studio.generate : L10n.Studio.configureModel,
                    systemImage: selectedModelIsReady ? "sparkles" : "externaldrive.badge.plus"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(generation.state.isRunning || isPreparingPrompt ||
                (selectedModelIsReady && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

            if shouldShowSimplePreview {
                Divider()
                Text(L10n.Studio.output).font(.headline)
                simplePreviewContent
            }
        }
        .padding(24)
        .frame(maxWidth: 760)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity)
    }

    private var simpleModelWarning: String {
        if appModel.nsfwFilterEnabled && modelLibrary.state(for: .nsfwClassifier) != .ready {
            return L10n.Studio.nsfwModelRequired
        }
        return L10n.Studio.modelRequired
    }

    private var shouldShowSimplePreview: Bool {
        if previewOverrideURL != nil { return true }
        if case .idle = generation.state { return false }
        return true
    }

    @ViewBuilder
    private var simplePreviewContent: some View {
        switch generation.state {
        case .completed(let url):
            simpleResultPreview(url: previewOverrideURL ?? url)
        case .idle:
            if let previewOverrideURL { simpleResultPreview(url: previewOverrideURL) }
        default:
            previewContent
        }
    }

    private func simpleResultPreview(url: URL) -> some View {
        Image(nsImage: NSImage(contentsOf: url) ?? NSImage())
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: 420)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                if appModel.nsfwFilterEnabled,
                   let assessment = currentVariant?.contentSafety ?? generation.record?.contentSafety,
                   assessment.needsCover,
                   revealedSafetyPreviewURL != url {
                    ContentSafetyCover(assessment: assessment) { revealedSafetyPreviewURL = url }
                }
            }
    }

    private var modeCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(L10n.Studio.mode)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 10) {
                    ForEach(GenerationMode.allCases) { option in
                        ModeButton(mode: option, isSelected: mode == option) {
                            mode = option
                            if option == .viewpointOrbit {
                                useViggleTurbo = false
                                useConsistencyLoRA = false
                                enhancePrompt = false
                                maskURL = nil
                                preparedPromptSource = nil
                                finalParentVariantID = nil
                            }
                            if !option.acceptsReferences {
                                referenceURLs.removeAll()
                                maskURL = nil
                            }
                            persistWorkspaceDraft()
                        }
                    }
                }
            }
        }
    }

    private var referencesCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(L10n.Studio.references, subtitle: mode == .viewpointOrbit
                    ? L10n.Studio.orbitReference : L10n.Studio.referencesSubtitle)

                if referenceURLs.isEmpty {
                    Button(action: chooseReferences) {
                        VStack(spacing: 9) {
                            Image(systemName: "photo.badge.plus")
                                .font(.title2)
                            Text(L10n.Studio.addReferences).fontWeight(.medium)
                            Text(mode == .viewpointOrbit ? "PNG / WebP" : L10n.Studio.noReferences)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 108)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(Array(referenceURLs.enumerated()), id: \.element) { index, url in
                                referenceChip(url, number: index + 1)
                            }
                            Button(action: chooseReferences) {
                                Image(systemName: "plus")
                                    .frame(width: 56, height: 56)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .disabled(referenceURLs.count >= (mode == .viewpointOrbit ? 1 : 10))
                        }
                    }
                    .scrollIndicators(.hidden)

                    if mode != .viewpointOrbit {
                        HStack {
                            Button(maskURL == nil ? L10n.Mask.create : L10n.Mask.edit, systemImage: "paintbrush.pointed") {
                                showMaskEditor = true
                            }
                            if maskURL != nil {
                                Text(L10n.Mask.active)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(L10n.Mask.remove, role: .destructive) {
                                    maskURL = nil
                                    persistWorkspaceDraft()
                                }
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
    }

    private var orbitCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(L10n.Studio.orbitTitle)
                Picker(L10n.Studio.orbitRotation, selection: Binding(
                    get: { orbitSettings.rotation },
                    set: { rotation in
                        var settings = orbitSettings
                        settings.rotation = rotation
                        if !settings.isValid { settings.elevation = .elevated }
                        orbitSettings = settings
                    }
                )) {
                    ForEach(ViewpointOrbitSettings.Rotation.allCases) { rotation in
                        Text(rotation.title).tag(rotation)
                    }
                }
                Picker(L10n.Studio.orbitElevation, selection: $orbitSettings.elevation) {
                    ForEach(ViewpointOrbitSettings.Elevation.allCases.filter {
                        orbitSettings.rotation != .keepAngle || $0 != .eyeLevel
                    }) { elevation in
                        Text(elevation.title).tag(elevation)
                    }
                }
                Text(L10n.Studio.orbitHelp)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Label(L10n.Studio.orbitSettings, systemImage: "square.on.square.dashed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if referenceURLs.count != 1 {
                    Label(L10n.Studio.orbitReference, systemImage: "photo.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if appModel.generationBackend != .diffusers {
                    Text(L10n.Studio.orbitFullModel).font(.callout)
                    Button(L10n.Studio.orbitSelectFullModel) {
                        appModel.generationBackend = .diffusers
                    }
                    .buttonStyle(.bordered)
                } else if modelLibrary.state(for: .viewpointOrbit) != .ready {
                    Button(L10n.Studio.orbitInstallRequired) { appModel.selection = .models }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func referenceChip(_ url: URL, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(nsImage: NSImage(contentsOf: url) ?? NSImage())
                .resizable()
                .scaledToFill()
                .frame(width: 86, height: 70)
                .clipped()
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    Text("\(number)")
                        .font(.caption2.bold())
                        .padding(5)
                        .background(.regularMaterial, in: Circle())
                        .padding(5)
                }
            HStack {
                Button(L10n.Studio.remove) {
                    let wasFirst = referenceURLs.first == url
                    referenceURLs.removeAll { $0 == url }
                    if wasFirst { maskURL = nil }
                    persistWorkspaceDraft()
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    referenceToDelete = url
                } label: {
                    Image(systemName: "trash")
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .help(L10n.Common.deletePermanently)
            }
            .frame(width: 86)
        }
    }

    private var promptCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(L10n.Studio.prompt, subtitle: L10n.Studio.promptSubtitle)
                TextEditor(text: $prompt)
                    .font(.body)
                    .focused($promptEditorFocused)
                    .scrollContentBackground(.hidden)
                    .padding(14)
                    .frame(height: 230)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                promptEditorFocused ? Color.accentColor : Color.primary.opacity(0.32),
                                lineWidth: promptEditorFocused ? 2 : 1
                            )
                    }
                    .overlay(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text(L10n.Studio.promptPlaceholder)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 19)
                                .padding(.vertical, 22)
                            .allowsHitTesting(false)
                        }
                    }

                HStack(spacing: 10) {
                    Button(L10n.Studio.resetPrompts, systemImage: "arrow.counterclockwise") {
                        resetPrompts()
                    }
                    .disabled(prompt.isEmpty && negativePrompt.isEmpty)

                    Button(L10n.Studio.promptHistory, systemImage: "clock.arrow.circlepath") {
                        appModel.selection = .prompts
                    }

                    Spacer()

                    if promptsWereSaved {
                        Label(L10n.Studio.promptsSaved, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    Button(L10n.Studio.savePrompts, systemImage: "square.and.arrow.down") {
                        savePrompts()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                promptGuide
            }
        }
    }

    private var promptGuide: some View {
        DisclosureGroup(L10n.Studio.promptGuide, isExpanded: $showPromptGuide) {
            VStack(alignment: .leading, spacing: 9) {
                Label(modePromptGuidance, systemImage: mode.systemImage)
                Label(L10n.Studio.guideText, systemImage: "textformat")
                if referenceURLs.count > 1 {
                    Label(L10n.Studio.guideReferences, systemImage: "photo.stack")
                }
                Label(L10n.Studio.guideSize, systemImage: "aspectratio")
                Label(L10n.Studio.guideCompare, systemImage: "square.on.square")
                if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(L10n.Studio.guidePreparedPrompt).fontWeight(.semibold)
                    Text(preset.applyingStyle(to: prompt.trimmingCharacters(in: .whitespacesAndNewlines)))
                        .textSelection(.enabled)
                }
                if mode == .edit && referenceURLs.isEmpty {
                    Label(L10n.Studio.guideMissingReference, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else if mode == .characterSheet && referenceURLs.isEmpty {
                    Label(L10n.Studio.guideCharacterReference, systemImage: "person.crop.rectangle")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
        }
    }

    private var promptResultCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeading(hasCurrentPreparedPrompt ? L10n.Studio.enhancedPrompt
                        : (displayedPromptResult?.title ?? L10n.Studio.enhancedPrompt))
                    Spacer()
                    if enhancePrompt {
                        Button(L10n.Studio.preparePrompt, systemImage: "sparkles") {
                            preparePromptBeforeGeneration()
                        }
                        .disabled(isPreparingPrompt || generation.state.isRunning
                            || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || modelLibrary.state(for: .promptEnhancer) != .ready
                            || !modelLibrary.canGenerate(using: appModel.generationBackend))
                    }
                    if isPreparingPrompt {
                        Button(L10n.Common.cancel) {
                            promptPreparationTask?.cancel()
                            promptPreparationID = nil
                            isPreparingPrompt = false
                        }
                    }
                    if let result = hasCurrentPreparedPrompt
                        ? (title: L10n.Studio.enhancedPrompt, value: preparedPrompt,
                           copyHelp: L10n.Studio.copyEnhancedPrompt)
                        : displayedPromptResult {
                        Button(
                            variantPromptWasSaved ? L10n.Studio.variantPromptSaved : L10n.Studio.saveVariantPrompt,
                            systemImage: variantPromptWasSaved ? "checkmark.circle.fill" : "square.and.arrow.down"
                        ) {
                            saveVariantPrompt(result.value)
                        }
                        .buttonStyle(.bordered)
                        .disabled(result.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(result.value, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help(result.copyHelp)
                    }
                }

                if let improved = transferableEnhancedPrompt {
                    Button(L10n.Studio.sendEnhancedToPrompt, systemImage: "arrow.up.left.square") {
                        sendEnhancedToPrompt(improved)
                    }
                    .buttonStyle(.bordered)
                    .help(L10n.Studio.sendEnhancedToPromptHelp)
                }

                if hasCurrentPreparedPrompt {
                    TextEditor(text: $preparedPrompt)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(height: 230)
                        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                    Picker(L10n.Studio.promptToUse, selection: $usePreparedPrompt) {
                        Text(L10n.Studio.originalPrompt).tag(false)
                        Text(L10n.Studio.enhancedPrompt).tag(true)
                    }
                    .pickerStyle(.segmented)
                    Text(L10n.Studio.promptChoiceHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        if isPreparingPrompt {
                            ProgressView(L10n.Studio.outputEnhancingPrompt)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if let result = displayedPromptResult {
                            Text(result.value)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if case .enhancingPrompt = generation.state {
                            ProgressView(L10n.Studio.outputEnhancingPrompt)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(L10n.Studio.enhancedPromptPlaceholder)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .contentMargins(12)
                    .frame(height: 230)
                    .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var modePromptGuidance: String {
        switch mode {
        case .create: L10n.Studio.guideCreate
        case .edit: L10n.Studio.guideEdit
        case .characterSheet: L10n.Studio.guideCharacter
        case .transparentAsset: L10n.Studio.guideTransparent
        case .viewpointOrbit: L10n.Studio.orbitHelp
        }
    }

    private var presetCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(L10n.Studio.preset)
                Picker(L10n.Studio.preset, selection: presetSelection) {
                    ForEach(GenerationPreset.allCases) { option in
                        Label(option.title, systemImage: option.systemImage)
                            .tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)

                Label {
                    Text(preset.detail)
                } icon: {
                    Image(systemName: preset.systemImage)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if preset != .fastDraft {
                    Button(L10n.Studio.prepareDraft, systemImage: "hare") {
                        preset = .fastDraft
                        resolution = GenerationPreset.fastDraft.resolution
                        steps = Double(GenerationPreset.fastDraft.steps)
                        if appModel.generationBackend == .diffusers,
                           modelLibrary.state(for: .viggleTurbo) == .ready,
                           referenceURLs.count <= 3, negativePrompt.isEmpty {
                            useConsistencyLoRA = false
                            useViggleTurbo = true
                        }
                        finalParentVariantID = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var presetSelection: Binding<GenerationPreset> {
        Binding(
            get: { preset },
            set: { value in
                preset = value
                resolution = value.resolution
                steps = Double(value.steps)
                syncSimpleCanvasSelection()
            }
        )
    }

    private var viggleSelection: Binding<Bool> {
        Binding(
            get: { useViggleTurbo },
            set: { enabled in
                useViggleTurbo = enabled
                if enabled { useConsistencyLoRA = false }
            }
        )
    }

    private var consistencySelection: Binding<Bool> {
        Binding(
            get: { useConsistencyLoRA },
            set: { enabled in
                useConsistencyLoRA = enabled
                if enabled { useViggleTurbo = false }
                persistWorkspaceDraft()
            }
        )
    }

    private var simpleFormatSelection: Binding<SimpleImageFormat> {
        Binding(
            get: { simpleImageFormat },
            set: { value in
                simpleImageFormat = value
                applySimpleCanvasSelection()
            }
        )
    }

    private var simpleSizeSelection: Binding<SimpleImageSize> {
        Binding(
            get: { simpleImageSize },
            set: { value in
                simpleImageSize = value
                applySimpleCanvasSelection()
            }
        )
    }

    private var simpleCanvas: (resolution: CanvasResolution, width: Int, height: Int) {
        switch (simpleImageFormat, simpleImageSize) {
        case (.square, .standard): (.square, 1_024, 1_024)
        case (.square, .large): (.square2K, 2_048, 2_048)
        case (.landscape, .standard): (.landscape, 1_344, 768)
        case (.landscape, .large): (.landscape2K, 2_048, 1_152)
        case (.portrait, .standard): (.portrait, 768, 1_344)
        case (.portrait, .large): (.portrait2K, 1_152, 2_048)
        case (.socialPortrait, .standard): (.socialPortrait, 1_024, 1_280)
        case (.socialPortrait, .large): (.custom, 1_536, 1_920)
        case (.ultrawide, .standard): (.ultrawide, 1_536, 672)
        case (.ultrawide, .large): (.custom, 2_048, 896)
        }
    }

    private func applySimpleCanvasSelection() {
        let canvas = simpleCanvas
        resolution = canvas.resolution
        if canvas.resolution == .custom {
            customWidth = canvas.width
            customHeight = canvas.height
        }
    }

    private func syncSimpleCanvasSelection() {
        simpleImageSize = max(
            resolution == .custom ? customWidth : resolution.width,
            resolution == .custom ? customHeight : resolution.height
        ) >= 1_800 ? .large : .standard

        switch resolution {
        case .square, .square2K: simpleImageFormat = .square
        case .landscape, .landscape2K: simpleImageFormat = .landscape
        case .portrait, .portrait2K: simpleImageFormat = .portrait
        case .socialPortrait: simpleImageFormat = .socialPortrait
        case .ultrawide: simpleImageFormat = .ultrawide
        case .custom:
            let ratio = Double(customWidth) / Double(max(customHeight, 1))
            simpleImageFormat = SimpleImageFormat.allCases.min {
                abs($0.aspectRatio - ratio) < abs($1.aspectRatio - ratio)
            } ?? .square
        }
    }

    private var previewCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(L10n.Studio.output)
                previewContent
                if let variant = currentVariant, !generation.state.isRunning {
                    reviewView(for: variant)
                }
            }
        }
    }

    private var displayedPromptRequest: GenerationRequest? {
        currentVariant?.request ?? generation.record?.request ?? previewRequest
    }

    private var promptPreviewSource: PromptPreviewSource {
        PromptPreviewSource(
            prompt: prompt,
            mode: mode,
            preset: preset,
            references: referenceURLs,
            backend: appModel.generationBackend
        )
    }

    private var hasCurrentPreparedPrompt: Bool {
        enhancePrompt && preparedPromptSource == promptPreviewSource
    }

    private var displayedPromptResult: (title: String, value: String, copyHelp: String)? {
        guard let request = displayedPromptRequest else { return nil }
        if let enhancedPrompt = request.enhancedPrompt {
            return (L10n.Studio.enhancedPrompt, enhancedPrompt, L10n.Studio.copyEnhancedPrompt)
        }
        guard !request.enhancePrompt else { return nil }
        return (L10n.Studio.finalPrompt, request.prompt, L10n.Studio.copyFinalPrompt)
    }

    private var transferableEnhancedPrompt: String? {
        let text = hasCurrentPreparedPrompt ? preparedPrompt : displayedPromptRequest?.enhancedPrompt
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private var currentVariant: ProjectVariant? {
        guard let currentVariantID else { return nil }
        return projectStore.activeProject?.variants.first { $0.id == currentVariantID }
    }

    private func reviewView(for variant: ProjectVariant) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(L10n.Studio.reviewTitle).font(.headline)
            Text(L10n.Studio.reviewChecklist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let width = variant.sourcePixelWidth, let height = variant.sourcePixelHeight {
                Text("\(L10n.Studio.reviewActualSize) : \(width) × \(height) px")
                    .font(.caption.monospacedDigit())
                if variant.kind == .generation || variant.kind == .variation {
                    Text("\(L10n.Studio.reviewRequestedSize) : \(variant.request.width) × \(variant.request.height) px")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if width != variant.request.width || height != variant.request.height {
                        Label(L10n.Studio.reviewSizeMismatch, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            if variant.request.mode.requestsTransparency, let previewHasTransparentPixels {
                Label(
                    previewHasTransparentPixels ? L10n.Studio.reviewAlphaPresent : L10n.Studio.reviewAlphaMissing,
                    systemImage: previewHasTransparentPixels ? "checkmark.circle" : "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(previewHasTransparentPixels ? Color.secondary : Color.orange)
            }

            Picker(L10n.Studio.reviewTitle, selection: $evaluation.verdict) {
                ForEach(ImageEvaluation.Verdict.allCases) { verdict in
                    Text(verdict.title).tag(verdict)
                }
            }
            .labelsHidden()

            if evaluation.verdict == .toCorrect {
                Text(L10n.Studio.reviewDefects).font(.caption.weight(.semibold))
                ForEach(ImageEvaluation.Issue.allCases) { issue in
                    Toggle(issue.title, isOn: Binding(
                        get: { evaluation.issues.contains(issue) },
                        set: { selected in
                            if selected {
                                if !evaluation.issues.contains(issue) { evaluation.issues.append(issue) }
                            } else {
                                evaluation.issues.removeAll { $0 == issue }
                            }
                        }
                    ))
                    .font(.caption)
                }
                TextField(L10n.Studio.reviewDefectNote, text: $evaluation.note, axis: .vertical)
                    .lineLimit(2...4)
            }
            TextField(L10n.Studio.reviewPreferenceNote, text: $evaluation.preferenceNote, axis: .vertical)
                .lineLimit(2...3)
            Button(L10n.Studio.reviewSave, systemImage: "checkmark.circle") {
                saveEvaluation(for: variant.id)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch generation.state {
        case .completed(let url):
            resultPreview(url: previewOverrideURL ?? url)
        case .switchingEngine:
            progressPreview(title: L10n.Studio.outputSwitchingEngine, progress: nil)
        case .preparing:
            progressPreview(title: L10n.Studio.outputPreparing, progress: nil)
        case .enhancingPrompt:
            progressPreview(title: L10n.Studio.outputEnhancingPrompt, progress: nil)
        case .generating(let progress):
            progressPreview(title: L10n.Studio.outputGenerating, progress: progress)
        case .screeningContent:
            progressPreview(title: L10n.Studio.outputScreeningContent, progress: nil)
        case .failed(let message):
            VStack(spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                Text(L10n.Studio.outputFailed).font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, minHeight: 210)
            .padding(12)
            .background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
        case .cancelled:
            emptyPreview(title: L10n.Studio.outputCancelled, symbol: "xmark.circle")
        case .idle:
            if let previewOverrideURL {
                resultPreview(url: previewOverrideURL)
            } else {
                emptyPreview(title: L10n.Studio.outputEmpty, symbol: mode.requestsTransparency ? "square.on.square.dashed" : "photo")
            }
        }
    }

    private func resultPreview(url: URL) -> some View {
        VStack(spacing: 10) {
            Image(nsImage: NSImage(contentsOf: url) ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 310)
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay {
                    if appModel.nsfwFilterEnabled,
                       let assessment = currentVariant?.contentSafety ?? generation.record?.contentSafety,
                       assessment.needsCover,
                       revealedSafetyPreviewURL != url {
                        ContentSafetyCover(assessment: assessment) { revealedSafetyPreviewURL = url }
                    }
                }
            Text(url.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if appModel.nsfwFilterEnabled,
               let variant = currentVariant,
               variant.contentSafety?.verdict == .unavailable {
                Button(isRetryingSafety ? L10n.Safety.retrying : L10n.Safety.retry,
                       systemImage: "arrow.clockwise") {
                    retrySafetyAssessment(for: variant)
                }
                .disabled(isRetryingSafety || generation.state.isRunning)
            }

            HStack(spacing: 8) {
                Button(L10n.Studio.variation, systemImage: "square.on.square") {
                    finalParentVariantID = nil
                    randomizeSeed = true
                    startGeneration(kind: .variation, parentID: currentVariantID)
                }
                .disabled(generation.state.isRunning || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Menu {
                    Button(L10n.Studio.upscale2x) { upscale(url, factor: 2) }
                    Button(L10n.Studio.upscale4x) { upscale(url, factor: 4) }
                } label: {
                    Label(isUpscaling ? "…" : "2× / 4×", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .disabled(isUpscaling || generation.state.isRunning)
            }

            if let variant = currentVariant, variant.request.preset == .fastDraft {
                Button(L10n.Studio.prepareFinal, systemImage: "sparkles.rectangle.stack") {
                    prepareFinalVersion(from: variant)
                }
                .buttonStyle(.bordered)
                .disabled(generation.state.isRunning || isUpscaling)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if currentVariant != nil {
                Button(L10n.Library.comparisonTitle, systemImage: "rectangle.split.2x1") {
                    appModel.selection = .library
                }
                .buttonStyle(.bordered)
                .disabled((projectStore.activeProject?.variants.count ?? 0) < 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                if (projectStore.activeProject?.variants.count ?? 0) < 2 {
                    Text(L10n.Studio.compareNeedsTwo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isUpscaling { ProgressView().controlSize(.small) }

            HStack {
                Button(L10n.Library.reveal, systemImage: "folder") {
                    ImageExportService.reveal(url)
                }
                Button(L10n.Library.saveAs, systemImage: "square.and.arrow.down") {
                    do {
                        try ImageExportService.saveCopy(of: url)
                    } catch {
                        exportError = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func emptyPreview(title: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 210)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 13))
    }

    private func progressPreview(title: String, progress: Double?) -> some View {
        VStack(spacing: 12) {
            if let progress {
                ProgressView(value: progress)
                    .controlSize(.large)
            } else {
                ProgressView()
                    .controlSize(.large)
            }
            Text(title).font(.callout.weight(.medium))
            if let progress {
                Text(progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let progress {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    if let remaining = remainingDuration(at: timeline.date, progress: progress) {
                        Text("\(L10n.Studio.estimatedRemaining) \(durationLabel(remaining))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let estimate = estimatedGenerationDuration,
                              let started = generation.record?.request.createdAt,
                              timeline.date.timeIntervalSince(started) >= estimate {
                        Text(L10n.Studio.estimateExceeded)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button(L10n.Studio.cancelGeneration, role: .cancel) { generation.cancel() }
                .font(.caption)
        }
        .frame(maxWidth: .infinity, minHeight: 210)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
    }

    private var settingsCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(L10n.Studio.settings)

                LabeledContent(L10n.Studio.engine) {
                    Picker(L10n.Studio.engine, selection: $appModel.generationBackend) {
                        ForEach(GenerationBackend.allCases) { backend in
                            Text(backend.choiceTitle).tag(backend)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                }

                Text(appModel.generationBackend.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ModelAdviceView(backend: appModel.generationBackend,
                                width: resolution == .custom ? customWidth : resolution.width,
                                height: resolution == .custom ? customHeight : resolution.height)

                if appModel.generationBackend == .diffusers && !orbitIsSelected {
                    HStack(spacing: 8) {
                        Toggle(L10n.Studio.viggleTurbo, isOn: viggleSelection)
                        Button {
                            showViggleHelp = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.Studio.viggleHelp)
                        .help(L10n.Studio.viggleHelp)
                        .popover(isPresented: $showViggleHelp) {
                            Text(L10n.Studio.viggleHelp)
                                .font(.callout)
                                .padding(16)
                                .frame(width: 290)
                        }
                    }
                    if useViggleTurbo && modelLibrary.canGenerate(using: .diffusers)
                        && modelLibrary.state(for: .viggleTurbo) != .ready {
                        Label(L10n.Studio.viggleInstallRequired, systemImage: "arrow.down.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if useViggleTurbo && referenceURLs.count > 3 {
                        Label(L10n.Studio.viggleMaxReferences, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if mode == .edit {
                        HStack(spacing: 8) {
                            Toggle(L10n.Studio.consistencyLoRA, isOn: consistencySelection)
                            Button {
                                showConsistencyHelp = true
                            } label: {
                                Image(systemName: "questionmark.circle")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.Studio.consistencyHelp)
                            .help(L10n.Studio.consistencyHelp)
                            .popover(isPresented: $showConsistencyHelp) {
                                Text(L10n.Studio.consistencyHelp)
                                    .font(.callout)
                                    .padding(16)
                                    .frame(width: 310)
                            }
                        }
                        if useConsistencyLoRA && modelLibrary.state(for: .consistencyLoRA) != .ready {
                            Label(L10n.Studio.consistencyInstallRequired, systemImage: "arrow.down.circle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if useConsistencyLoRA && referenceURLs.count != 1 {
                            Label(L10n.Studio.consistencyOneReference, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if useConsistencyLoRA, let referenceSize = consistencyReferenceSize,
                           referenceSize.width != (resolution == .custom ? customWidth : resolution.width)
                            || referenceSize.height != (resolution == .custom ? customHeight : resolution.height) {
                            Label(L10n.Studio.consistencySizeMismatch, systemImage: "aspectratio")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            if CanvasResolution.isValidCustomDimension(referenceSize.width)
                                && CanvasResolution.isValidCustomDimension(referenceSize.height) {
                                Button(L10n.Studio.consistencyMatchReference) {
                                    resolution = .custom
                                    customWidth = referenceSize.width
                                    customHeight = referenceSize.height
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        if useConsistencyLoRA && consistencyUsesUntestedResolution {
                            Label(L10n.Studio.consistencyHighResolution, systemImage: "memorychip")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if orbitIsSelected {
                    Text(L10n.Studio.orbitSettings)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent(L10n.Studio.resolution) {
                        Picker(L10n.Studio.resolution, selection: $resolution) {
                            ForEach(CanvasResolution.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 176)
                    }

                    if resolution == .custom {
                        customResolutionEditor
                    }

                    if usesHighResolution {
                        Label(L10n.Studio.highResolutionWarning, systemImage: "memorychip")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                DisclosureGroup(L10n.Studio.advanced, isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(L10n.Studio.steps)
                            Spacer()
                            Text(appModel.generationBackend.fixedStepCount.map(String.init) ?? (orbitIsSelected ? "40" : (useViggleTurbo && appModel.generationBackend == .diffusers ? "6" : "\(Int(steps))")))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $steps, in: 10...50, step: 1)
                            .disabled(appModel.generationBackend.fixedStepCount != nil || orbitIsSelected || (useViggleTurbo && appModel.generationBackend == .diffusers))

                        Toggle(L10n.Studio.randomSeed, isOn: $randomizeSeed)
                        if !randomizeSeed {
                            Stepper("\(L10n.Studio.seed): \(seed)", value: $seed, in: 0...Int(Int32.max))
                        }
                        Toggle(L10n.Studio.enhancePrompt, isOn: $enhancePrompt)
                            .disabled(orbitIsSelected)
                        if enhancePrompt && !hasCurrentPreparedPrompt
                            && modelLibrary.state(for: .promptEnhancer) != .ready {
                            Text(L10n.Studio.enhancerInstallRequired)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        TextField(L10n.Studio.negativePlaceholder, text: $negativePrompt, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!appModel.generationBackend.supportsNegativePrompt || orbitIsSelected || (useViggleTurbo && appModel.generationBackend == .diffusers)
                                || consistencyIsSelected)
                    }
                    .padding(.top, 12)
                }

                Divider()

                if let estimate = estimatedGenerationDuration {
                    Label("\(L10n.Studio.estimatedDuration) \(durationLabel(estimate))", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label(L10n.Studio.estimateUnavailable, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if finalParentVariantID != nil {
                    Label(L10n.Studio.finalReady, systemImage: "sparkles.rectangle.stack")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if orbitIsSelected && appModel.generationBackend != .diffusers {
                    Label(L10n.Studio.orbitFullModel, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if orbitIsSelected && modelLibrary.state(for: .viewpointOrbit) != .ready {
                    Label(L10n.Studio.orbitInstallRequired, systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !selectedModelIsReady {
                    Label(
                        appModel.nsfwFilterEnabled && modelLibrary.state(for: .nsfwClassifier) != .ready
                            ? L10n.Studio.nsfwModelRequired
                            : (useViggleTurbo && appModel.generationBackend == .diffusers
                            && modelLibrary.canGenerate(using: .diffusers)
                            && modelLibrary.state(for: .viggleTurbo) != .ready
                            ? L10n.Studio.viggleInstallRequired
                            : (enhancePrompt
                                && modelLibrary.state(for: .promptEnhancer) != .ready
                                ? L10n.Studio.enhancerInstallRequired : L10n.Studio.modelRequired)),
                        systemImage: "exclamationmark.triangle"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if case .failed = generation.state {
                    Label(L10n.Studio.runtimeRequired, systemImage: "gearshape.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    startGeneration()
                } label: {
                    Label(
                        selectedModelIsReady
                            ? (finalParentVariantID == nil ? L10n.Studio.generate : L10n.Studio.generateFinal)
                            : L10n.Studio.configureModel,
                        systemImage: selectedModelIsReady ? "sparkles" : "externaldrive.badge.plus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(
                    generation.state.isRunning || isPreparingPrompt ||
                    (!orbitIsSelected && hasCurrentPreparedPrompt && usePreparedPrompt
                        && preparedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
                    (selectedModelIsReady && !orbitIsSelected && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
                    (selectedModelIsReady && orbitIsSelected && (referenceURLs.count != 1 || !orbitSettings.isValid)) ||
                    (selectedModelIsReady && mode == .edit && referenceURLs.isEmpty) ||
                    (selectedModelIsReady && useViggleTurbo && appModel.generationBackend == .diffusers
                        && referenceURLs.count > 3) ||
                    (selectedModelIsReady && consistencyIsSelected && referenceURLs.count != 1) ||
                    (selectedModelIsReady && !customResolutionIsValid)
                )
            }
        }
    }

    private func chooseReferences() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = mode == .viewpointOrbit ? [.png, .webP] : [.png, .jpeg, .heic, .webP]
        panel.allowsMultipleSelection = mode != .viewpointOrbit
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }
        let availableSlots = max(0, (mode == .viewpointOrbit ? 1 : 10) - referenceURLs.count)
        referenceURLs.append(contentsOf: panel.urls.prefix(availableSlots).filter { !referenceURLs.contains($0) })
        persistWorkspaceDraft()
    }

    @discardableResult
    private func persistWorkspaceDraft(persistPrompts: Bool = false) -> Bool {
        let previousRequest = projectStore.activeProject?.draft
            ?? projectStore.activeProject?.variants.max(by: { $0.createdAt < $1.createdAt })?.request
        var request = GenerationRequest(
            mode: mode,
            preset: preset,
            prompt: persistPrompts ? prompt : (previousRequest?.originalPrompt ?? previousRequest?.prompt ?? prompt),
            negativePrompt: appModel.generationBackend.supportsNegativePrompt
                ? (persistPrompts ? negativePrompt : (previousRequest?.negativePrompt ?? negativePrompt)) : "",
            resolution: resolution,
            customWidth: resolution == .custom ? customWidth : nil,
            customHeight: resolution == .custom ? customHeight : nil,
            steps: appModel.generationBackend.fixedStepCount ?? (useViggleTurbo && appModel.generationBackend == .diffusers ? 6 : Int(steps)),
            seed: UInt32(seed),
            randomizeSeed: randomizeSeed,
            enhancePrompt: enhancePrompt,
            useViggleTurbo: useViggleTurbo && appModel.generationBackend == .diffusers,
            useConsistencyLoRA: useConsistencyLoRA && mode == .edit
                && appModel.generationBackend == .diffusers && !useViggleTurbo,
            backend: appModel.generationBackend,
            referenceImages: referenceURLs,
            maskImage: maskURL
        )
        if mode == .viewpointOrbit { request.configureViewpointOrbit(orbitSettings) }
        do {
            let archivedRequest = try projectStore.saveActiveProjectDraft(request)
            referenceURLs = archivedRequest.referenceImages
            maskURL = archivedRequest.maskImage
            return true
        } catch {
            exportError = error.localizedDescription
            return false
        }
    }

    private func resetPrompts() {
        prompt = ""
        negativePrompt = ""
        promptsWereSaved = false
    }

    private func savePrompts() {
        guard persistWorkspaceDraft(persistPrompts: true) else {
            promptsWereSaved = false
            return
        }
        do {
            try projectStore.savePrompt(prompt: prompt, negativePrompt: negativePrompt)
            promptsWereSaved = true
        } catch {
            promptsWereSaved = false
            exportError = error.localizedDescription
        }
    }

    private func saveVariantPrompt(_ value: String) {
        do {
            try projectStore.savePrompt(
                prompt: value,
                negativePrompt: hasCurrentPreparedPrompt
                    ? negativePrompt : (displayedPromptRequest?.negativePrompt ?? "")
            )
            variantPromptWasSaved = true
        } catch {
            variantPromptWasSaved = false
            exportError = error.localizedDescription
        }
    }

    private func sendEnhancedToPrompt(_ value: String) {
        prompt = value
        enhancePrompt = false
        preset = .none
        preparedPromptSource = nil
        promptsWereSaved = false
        promptEditorFocused = true
    }

    private func openRequestedPrompt() {
        if let id = appModel.promptToOpenID {
            if let savedPrompt = projectStore.savedPrompts.first(where: { $0.id == id }) {
                prompt = savedPrompt.prompt
                negativePrompt = savedPrompt.negativePrompt
                promptsWereSaved = false
            }
            appModel.promptToOpenID = nil
        }
        if let selection = appModel.promptHistoryToOpen {
            if let entry = projectStore.promptHistory.first(where: { $0.id == selection.id }) {
                prompt = selection.useOriginal ? entry.originalPrompt : entry.usedPrompt
                negativePrompt = entry.negativePrompt
                enhancePrompt = false
                preset = .none
                promptsWereSaved = false
            }
            appModel.promptHistoryToOpen = nil
        }
    }

    private func deletePendingReference() {
        guard let url = referenceToDelete else { return }
        referenceToDelete = nil
        do {
            try projectStore.permanentlyDeleteReference(url)
            let wasFirst = referenceURLs.first == url
            referenceURLs.removeAll { $0 == url }
            if wasFirst { maskURL = nil }
            persistWorkspaceDraft()
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func refreshModelAvailability() {
        modelLibrary.refresh(in: storage.modelsURL)
    }

    private func makeGenerationRequest() -> GenerationRequest {
        let turboSelected = isExpertMode && !orbitIsSelected && appModel.generationBackend == .diffusers && useViggleTurbo
        let selectedCanvas = simpleCanvas
        var request = GenerationRequest(
            mode: isExpertMode ? mode : .create,
            preset: preset,
            prompt: preset.applyingStyle(to: prompt.trimmingCharacters(in: .whitespacesAndNewlines)),
            originalPrompt: prompt,
            negativePrompt: appModel.generationBackend.supportsNegativePrompt && isExpertMode && !consistencyIsSelected
                ? negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            resolution: isExpertMode ? resolution : selectedCanvas.resolution,
            customWidth: isExpertMode
                ? (resolution == .custom ? customWidth : nil)
                : (selectedCanvas.resolution == .custom ? selectedCanvas.width : nil),
            customHeight: isExpertMode
                ? (resolution == .custom ? customHeight : nil)
                : (selectedCanvas.resolution == .custom ? selectedCanvas.height : nil),
            steps: appModel.generationBackend.fixedStepCount ?? (isExpertMode ? (turboSelected ? 6 : Int(steps)) : preset.steps),
            seed: UInt32(seed),
            randomizeSeed: isExpertMode ? randomizeSeed : true,
            enhancePrompt: isExpertMode && enhancePrompt,
            useViggleTurbo: turboSelected,
            useConsistencyLoRA: consistencyIsSelected && !turboSelected,
            backend: appModel.generationBackend,
            referenceImages: isExpertMode ? referenceURLs : [],
            maskImage: isExpertMode ? maskURL : nil
        )
        if orbitIsSelected { request.configureViewpointOrbit(orbitSettings) }
        return request
    }

    private func preparePromptBeforeGeneration() {
        guard !isPreparingPrompt,
              !generation.state.isRunning,
              !orbitIsSelected,
              let enhancerRoot = modelLibrary.installationURL(for: .promptEnhancer),
              let modelRoot = modelLibrary.installationURL(for: appModel.generationBackend.modelPackage) else {
            return
        }
        let source = promptPreviewSource
        let request = makeGenerationRequest()
        let previousPreparation = promptPreparationTask
        let preparationID = UUID()
        promptPreparationID = preparationID
        isPreparingPrompt = true
        promptPreparationTask = Task {
            await previousPreparation?.value
            guard !Task.isCancelled, promptPreparationID == preparationID else { return }
            do {
                let result = try await generation.preparePrompt(
                    request: request,
                    modelRoot: enhancerRoot,
                    runtimeModelRoot: modelRoot,
                    outputDirectory: FileManager.default.temporaryDirectory
                )
                guard !Task.isCancelled, promptPreparationID == preparationID,
                      source == promptPreviewSource else { return }
                preparedPrompt = result
                preparedPromptSource = source
                usePreparedPrompt = true
                variantPromptWasSaved = false
            } catch is CancellationError {
                // The text changed or the view closed while the preview was running.
            } catch {
                if !Task.isCancelled && promptPreparationID == preparationID {
                    exportError = error.localizedDescription
                }
            }
            if promptPreparationID == preparationID {
                isPreparingPrompt = false
                promptPreparationTask = nil
                promptPreparationID = nil
            }
        }
    }

    private func prepareFinalVersion(from draft: ProjectVariant) {
        projectStore.variantToOpenID = draft.id
        loadActiveProject()
        preset = .none
        steps = max(40, steps)
        useViggleTurbo = false
        finalParentVariantID = draft.id
        if let enhanced = draft.request.enhancedPrompt,
           !enhanced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            preparedPrompt = enhanced
            preparedPromptSource = promptPreviewSource
            usePreparedPrompt = true
        }
    }

    private var estimatedGenerationDuration: TimeInterval? {
        let target = makeGenerationRequest()
        let samples = projectStore.projects
            .flatMap(\.variants)
            .filter { $0.kind == .generation || $0.kind == .variation }
            .filter { $0.request.backend == target.backend
                && $0.request.useViggleTurbo == target.useViggleTurbo
                && $0.request.useConsistencyLoRA == target.useConsistencyLoRA
                && ($0.request.mode == .viewpointOrbit) == (target.mode == .viewpointOrbit) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(8)
            .compactMap { variant -> TimeInterval? in
                let duration = variant.createdAt.timeIntervalSince(variant.request.createdAt)
                guard (5...14_400).contains(duration), variant.request.steps > 0 else { return nil }
                let pixelRatio = Double(target.width * target.height)
                    / Double(variant.request.width * variant.request.height)
                let stepRatio = Double(target.steps) / Double(variant.request.steps)
                return min(14_400, duration * pixelRatio * stepRatio)
            }
            .sorted()
        guard !samples.isEmpty else { return nil }
        return samples[samples.count / 2]
    }

    private func remainingDuration(at date: Date, progress: Double) -> TimeInterval? {
        if progress >= 0.10, progress < 1,
           let started = generation.generatingStartedAt {
            let generatingElapsed = max(0, date.timeIntervalSince(started))
            if generatingElapsed > 5 {
                return min(14_400, generatingElapsed * (1 - progress) / progress)
            }
        }
        guard let estimate = estimatedGenerationDuration,
              let started = generation.record?.request.createdAt else { return nil }
        let remaining = estimate - date.timeIntervalSince(started)
        return remaining > 0 ? remaining : nil
    }

    private func durationLabel(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        return "~\(minutes) min"
    }

    private func startGeneration(
        kind: ProjectVariant.Kind = .generation,
        parentID: UUID? = nil
    ) {
        refreshModelAvailability()
        guard !isPreparingPrompt else { return }
        if isExpertMode && !orbitIsSelected && hasCurrentPreparedPrompt && usePreparedPrompt
            && preparedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            exportError = L10n.Studio.preparedPromptEmpty
            return
        }
        if orbitIsSelected && (referenceURLs.count != 1 || !orbitSettings.isValid) {
            exportError = L10n.Studio.orbitReference
            return
        }
        let turboSelected = isExpertMode && !orbitIsSelected && appModel.generationBackend == .diffusers && useViggleTurbo
        guard !turboSelected || referenceURLs.count <= 3 else {
            exportError = L10n.Studio.viggleMaxReferences
            return
        }
        guard !consistencyIsSelected || referenceURLs.count == 1 else {
            exportError = L10n.Studio.consistencyOneReference
            return
        }
        let package = appModel.generationBackend.modelPackage
        guard appModel.generationBackend.advice.rating != .incompatible,
              modelLibrary.canGenerate(using: appModel.generationBackend),
              (!turboSelected || modelLibrary.state(for: .viggleTurbo) == .ready),
              (!consistencyIsSelected || modelLibrary.state(for: .consistencyLoRA) == .ready),
              (!orbitIsSelected || (appModel.generationBackend == .diffusers && modelLibrary.state(for: .viewpointOrbit) == .ready)),
              (!isExpertMode || orbitIsSelected || !enhancePrompt || hasCurrentPreparedPrompt
                || modelLibrary.state(for: .promptEnhancer) == .ready),
              (!appModel.nsfwFilterEnabled || modelLibrary.state(for: .nsfwClassifier) == .ready),
              let modelRoot = modelLibrary.installationURL(for: package) else {
            appModel.selection = .models
            return
        }

        do {
            projectStore.configure(rootURL: storage.generationOutputURL)
            let outputDirectory = try projectStore.imagesDirectoryForActiveProject()
            var request = makeGenerationRequest()
            if isExpertMode && !orbitIsSelected && hasCurrentPreparedPrompt {
                if usePreparedPrompt {
                    request.enhancedPrompt = preparedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    request.enhancePrompt = false
                }
            }
            preparedPromptSource = nil
            pendingVariantKind = finalParentVariantID == nil ? kind : .variation
            pendingParentVariantID = finalParentVariantID ?? parentID
            finalParentVariantID = nil
            lastPersistedOutputURL = nil
            previewOverrideURL = nil
            revealedSafetyPreviewURL = nil
            previewRequest = request
            currentVariantID = nil
            keepStartupPreviewEmpty = false
            variantPromptWasSaved = false
            evaluation = ImageEvaluation()
            previewHasTransparentPixels = nil
            generation.generate(
                request: request,
                modelRoot: modelRoot,
                promptEnhancerRoot: request.enhancePrompt && request.enhancedPrompt == nil
                    ? modelLibrary.installationURL(for: .promptEnhancer) : nil,
                outputDirectory: outputDirectory,
                backend: appModel.generationBackend,
                safetyFilterEnabled: appModel.nsfwFilterEnabled,
                safetyModelRoot: appModel.nsfwFilterEnabled
                    ? modelLibrary.installationURL(for: .nsfwClassifier) : nil
            )
        } catch {
            // Le coordinateur fournit un état d'erreur uniforme, même lorsqu'un dossier de sortie est indisponible.
            generation.report(error: error)
        }
    }

    private func persistCompletedGeneration(_ url: URL) {
        guard lastPersistedOutputURL != url,
              let request = generation.record?.request else { return }
        do {
            let variant = try projectStore.addVariant(
                outputURL: url,
                request: request,
                kind: pendingVariantKind,
                parentID: pendingParentVariantID,
                contentSafety: generation.record?.contentSafety
            )
            currentVariantID = variant.id
            previewRequest = variant.request
            previewOverrideURL = projectStore.activeProject.map { projectStore.imageURL(for: variant, in: $0) }
            loadEvaluation(for: variant, imageURL: previewOverrideURL)
            lastPersistedOutputURL = url
            if let project = projectStore.activeProject {
                do {
                    try projectStore.recordPromptHistory(
                        request: variant.request,
                        createdAt: variant.createdAt,
                        projectName: project.name
                    )
                } catch {
                    exportError = error.localizedDescription
                }
            }
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func upscale(_ source: URL, factor: Int) {
        guard let request = previewRequest ?? generation.record?.request else { return }
        let sourceAssessment = currentVariant?.contentSafety
        isUpscaling = true
        Task {
            do {
                let directory = try projectStore.imagesDirectoryForActiveProject()
                let output = try await Self.upscaler.upscale(
                    source: source,
                    factor: factor,
                    outputDirectory: directory
                )
                var assessment = sourceAssessment
                if appModel.nsfwFilterEnabled {
                    if let modelRoot = modelLibrary.installationURL(for: .nsfwClassifier),
                       let libraryRoot = storage.modelsURL {
                        do {
                            let score = try await Self.safetyClassifier.classify(
                                imageURL: output,
                                modelRoot: modelRoot,
                                runtimeModelRoot: libraryRoot,
                                outputDirectory: directory
                            )
                            assessment = ContentSafetyAssessment(nsfwProbability: score)
                        } catch {
                            assessment = .unavailable
                            await AppLog.shared.append(.error, category: "ContentSafety", error.localizedDescription)
                        }
                    } else {
                        assessment = .unavailable
                    }
                }
                let kind: ProjectVariant.Kind = factor == 2 ? .upscale2x : .upscale4x
                let variant = try projectStore.addVariant(
                    outputURL: output,
                    request: request,
                    kind: kind,
                    parentID: currentVariantID,
                    contentSafety: assessment
                )
                currentVariantID = variant.id
                previewRequest = variant.request
                previewOverrideURL = output
                revealedSafetyPreviewURL = nil
                loadEvaluation(for: variant, imageURL: output)
            } catch {
                exportError = error.localizedDescription
            }
            isUpscaling = false
        }
    }

    private func retrySafetyAssessment(for variant: ProjectVariant) {
        guard appModel.nsfwFilterEnabled, !isRetryingSafety, !isUpscaling,
              let project = projectStore.activeProject else { return }
        guard let modelRoot = modelLibrary.installationURL(for: .nsfwClassifier),
              let libraryRoot = storage.modelsURL else {
            exportError = L10n.Studio.nsfwModelRequired
            return
        }

        let imageURL = projectStore.imageURL(for: variant, in: project)
        isRetryingSafety = true
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
                revealedSafetyPreviewURL = nil
            } catch {
                exportError = error.localizedDescription
                await AppLog.shared.append(.error, category: "ContentSafety", error.localizedDescription)
            }
            isRetryingSafety = false
        }
    }

    private func loadActiveProject(restorePrompts: Bool = true) {
        guard let project = projectStore.activeProject else {
            clearWorkspace()
            return
        }
        let requestedVariant = projectStore.variantToOpenID.flatMap { requestedID in
            project.variants.first { $0.id == requestedID }
        }
        projectStore.variantToOpenID = nil
        let variant = requestedVariant ?? project.variants.sorted(by: { $0.createdAt < $1.createdAt }).last
        guard let request = requestedVariant?.request ?? project.draft ?? variant?.request else {
            clearWorkspace()
            return
        }
        if restorePrompts {
            currentVariantID = variant?.id
            previewRequest = variant?.request ?? request
            previewOverrideURL = variant.map { projectStore.imageURL(for: $0, in: project) }
            loadEvaluation(for: variant, imageURL: previewOverrideURL)
            if appModel.nsfwFilterEnabled,
               let variant,
               variant.contentSafety?.verdict == .unavailable,
               !retriedSafetyVariantIDs.contains(variant.id) {
                retriedSafetyVariantIDs.insert(variant.id)
                retrySafetyAssessment(for: variant)
            }
        } else {
            generation.resetPresentation()
            currentVariantID = nil
            previewRequest = nil
            previewOverrideURL = nil
            evaluation = ImageEvaluation()
            previewHasTransparentPixels = nil
        }
        variantPromptWasSaved = false
        if projectStore.variantToRegenerateID == nil, let backend = request.backend {
            appModel.generationBackend = backend
        }
        mode = request.mode
        preset = restorePrompts ? request.preset : .none
        prompt = restorePrompts ? (request.originalPrompt ?? request.prompt) : L10n.Studio.defaultPrompt
        negativePrompt = restorePrompts ? request.negativePrompt : ""
        promptsWereSaved = false
        resolution = restorePrompts ? request.resolution : .square
        customWidth = request.customWidth ?? request.width
        customHeight = request.customHeight ?? request.height
        syncSimpleCanvasSelection()
        steps = restorePrompts
            ? (request.useViggleTurbo == true ? Double(request.preset.steps) : Double(request.steps))
            : Double(GenerationPreset.none.steps)
        seed = Int(request.seed)
        randomizeSeed = request.randomizeSeed
        enhancePrompt = request.enhancePrompt
        useViggleTurbo = request.useViggleTurbo == true
        useConsistencyLoRA = request.useConsistencyLoRA == true
        orbitSettings = request.viewpointOrbit ?? ViewpointOrbitSettings()
        referenceURLs = request.referenceImages
        maskURL = request.maskImage
    }

    private func clearWorkspace() {
        generation.resetPresentation()
        finalParentVariantID = nil
        preset = .none
        resolution = .square
        simpleImageFormat = .square
        simpleImageSize = .standard
        steps = Double(GenerationPreset.none.steps)
        previewOverrideURL = nil
        previewRequest = nil
        currentVariantID = nil
        evaluation = ImageEvaluation()
        previewHasTransparentPixels = nil
        variantPromptWasSaved = false
        maskURL = nil
        referenceURLs = []
        prompt = L10n.Studio.defaultPrompt
        negativePrompt = ""
        enhancePrompt = modelLibrary.state(for: .promptEnhancer) == .ready
        useConsistencyLoRA = false
        orbitSettings = ViewpointOrbitSettings()
        promptsWereSaved = false
    }

    private func loadEvaluation(for variant: ProjectVariant?, imageURL: URL?) {
        evaluation = variant?.evaluation ?? ImageEvaluation()
        guard variant?.request.mode.requestsTransparency == true,
              let imageURL,
              let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            previewHasTransparentPixels = nil
            return
        }
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            previewHasTransparentPixels = false
        default:
            let pixelCount = image.width * image.height
            guard pixelCount <= 16_777_216 else {
                previewHasTransparentPixels = nil
                return
            }
            var pixels = [UInt8](repeating: 0, count: pixelCount * 4)
            previewHasTransparentPixels = pixels.withUnsafeMutableBytes { bytes in
                guard let context = CGContext(
                    data: bytes.baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
                ) else { return nil }
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                return stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] < 255 }
            }
        }
    }

    private func saveEvaluation(for variantID: UUID) {
        var updated = evaluation
        if updated.verdict != .toCorrect {
            updated.issues = []
            updated.note = ""
        }
        updated.reviewedAt = updated.verdict == .toReview ? nil : Date()
        do {
            try projectStore.saveEvaluation(updated, for: variantID)
            evaluation = updated
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func renameActiveProject() {
        guard let project = projectStore.activeProject else { return }
        let field = NSTextField(string: project.name)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        let alert = NSAlert()
        alert.messageText = L10n.Project.rename
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.Characters.save)
        alert.addButton(withTitle: L10n.Characters.cancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try projectStore.renameActiveProject(to: field.stringValue)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private var selectedModelIsReady: Bool {
        modelLibrary.canGenerate(using: appModel.generationBackend)
            && (!appModel.nsfwFilterEnabled || modelLibrary.state(for: .nsfwClassifier) == .ready)
            && (!isExpertMode || orbitIsSelected || appModel.generationBackend != .diffusers || !useViggleTurbo
                || modelLibrary.state(for: .viggleTurbo) == .ready)
            && (!consistencyIsSelected || modelLibrary.state(for: .consistencyLoRA) == .ready)
            && (!orbitIsSelected || (appModel.generationBackend == .diffusers && modelLibrary.state(for: .viewpointOrbit) == .ready))
            && (!isExpertMode || orbitIsSelected || !enhancePrompt || hasCurrentPreparedPrompt
                || modelLibrary.state(for: .promptEnhancer) == .ready)
    }

    private var orbitIsSelected: Bool { isExpertMode && mode == .viewpointOrbit }

    private var consistencyIsSelected: Bool {
        isExpertMode && appModel.generationBackend == .diffusers && mode == .edit && useConsistencyLoRA
    }

    private var consistencyReferenceSize: (width: Int, height: Int)? {
        guard referenceURLs.count == 1,
              let source = CGImageSourceCreateWithURL(referenceURLs[0] as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
              let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue else {
            return nil
        }
        return (width, height)
    }

    private var consistencyUsesUntestedResolution: Bool {
        let width = resolution == .custom ? customWidth : resolution.width
        let height = resolution == .custom ? customHeight : resolution.height
        return width * height > 1_500_000
    }

    private var validProjectSelection: Binding<UUID?> {
        Binding(
            get: {
                guard let activeProjectID = projectStore.activeProjectID,
                      projectStore.projects.contains(where: { $0.id == activeProjectID }) else {
                    return nil
                }
                return activeProjectID
            },
            set: {
                keepStartupPreviewEmpty = false
                projectStore.activeProjectID = $0
            }
        )
    }

    private var customResolutionIsValid: Bool {
        orbitIsSelected || resolution != .custom || (
            CanvasResolution.isValidCustomDimension(customWidth) &&
            CanvasResolution.isValidCustomDimension(customHeight)
        )
    }

    private var usesHighResolution: Bool {
        let width = resolution == .custom ? customWidth : resolution.width
        let height = resolution == .custom ? customHeight : resolution.height
        return width >= 2_048 || height >= 2_048
    }

    private var customResolutionEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(L10n.Studio.width, value: $customWidth, format: .number)
                    .textFieldStyle(.roundedBorder)
                Text("×").foregroundStyle(.secondary)
                TextField(L10n.Studio.height, value: $customHeight, format: .number)
                    .textFieldStyle(.roundedBorder)
                Button {
                    (customWidth, customHeight) = (customHeight, customWidth)
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .help(L10n.Studio.swapDimensions)
            }

            Text(L10n.Studio.customResolutionHint)
                .font(.caption2)
                .foregroundStyle(customResolutionIsValid ? Color.secondary : Color.red)
        }
    }
}
