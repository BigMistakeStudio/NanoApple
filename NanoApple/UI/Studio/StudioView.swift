import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct StudioView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var storage: SecurityScopedStorage
    @EnvironmentObject private var modelLibrary: ModelLibrary
    @EnvironmentObject private var generation: GenerationCoordinator
    @EnvironmentObject private var projectStore: ProjectStore

    @State private var mode: GenerationMode = .create
    @State private var preset: GenerationPreset = .balanced
    @State private var prompt = L10n.Studio.defaultPrompt
    @State private var negativePrompt = ""
    @State private var referenceURLs: [URL] = []
    @State private var resolution: CanvasResolution = .square
    @State private var customWidth = 1_024
    @State private var customHeight = 1_024
    @State private var steps = 30.0
    @State private var seed = 42
    @State private var randomizeSeed = true
    @State private var enhancePrompt = true
    @State private var useViggleTurbo = false
    @State private var showViggleHelp = false
    @State private var showAdvanced = false
    @State private var exportError: String?
    @State private var maskURL: URL?
    @State private var showMaskEditor = false
    @State private var previewOverrideURL: URL?
    @State private var previewRequest: GenerationRequest?
    @State private var currentVariantID: UUID?
    @State private var pendingVariantKind: ProjectVariant.Kind = .generation
    @State private var pendingParentVariantID: UUID?
    @State private var lastPersistedOutputURL: URL?
    @State private var isUpscaling = false
    @State private var referenceToDelete: URL?
    @State private var loadedProjectID: UUID?
    @State private var promptsWereSaved = false
    @State private var showPromptGuide = false
    @State private var evaluation = ImageEvaluation()
    @State private var previewHasTransparentPixels: Bool?

    private static let upscaler = ImageUpscaler()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 18) {
                        modeCard
                        if mode.acceptsReferences { referencesCard }
                        promptCard
                        if enhancePrompt || displayedPromptResult != nil {
                            promptResultCard
                        }
                        presetCard
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 18) {
                        previewCard
                        settingsCard
                    }
                    .frame(width: 330)
                }
            }
            .padding(28)
            .frame(maxWidth: 1_280)
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
        .onChange(of: preset) { _, value in
            resolution = value.resolution
            steps = Double(value.steps)
        }
        .onChange(of: appModel.generationBackend) { _, backend in
            if backend == .ggufQ6 { enhancePrompt = false }
            refreshModelAvailability()
        }
        .onAppear {
            refreshModelAvailability()
            projectStore.configure(rootURL: storage.generationOutputURL)
            let shouldRestorePrompts = appModel.didInitializeStudioPrompts
            appModel.didInitializeStudioPrompts = true
            loadedProjectID = projectStore.activeProjectID
            loadActiveProject(restorePrompts: shouldRestorePrompts)
            openRequestedPrompt()
        }
        .onChange(of: projectStore.activeProjectID) { _, newValue in
            guard newValue != loadedProjectID else { return }
            loadedProjectID = newValue
            loadActiveProject()
        }
        .onChange(of: prompt) { _, _ in promptsWereSaved = false }
        .onChange(of: negativePrompt) { _, _ in promptsWereSaved = false }
        .onChange(of: useViggleTurbo) { _, _ in persistWorkspaceDraft() }
        .onChange(of: appModel.promptToOpenID) { _, _ in openRequestedPrompt() }
        .onChange(of: generation.state) { _, state in
            if case .completed(let url) = state { persistCompletedGeneration(url) }
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
                Text(L10n.Studio.subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
    }

    private var modeCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(L10n.Studio.mode)
                HStack(spacing: 10) {
                    ForEach(GenerationMode.allCases) { option in
                        ModeButton(mode: option, isSelected: mode == option) {
                            mode = option
                            if !option.acceptsReferences {
                                referenceURLs.removeAll()
                                maskURL = nil
                                persistWorkspaceDraft()
                            }
                        }
                    }
                }
            }
        }
    }

    private var referencesCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(L10n.Studio.references, subtitle: L10n.Studio.referencesSubtitle)

                if referenceURLs.isEmpty {
                    Button(action: chooseReferences) {
                        VStack(spacing: 9) {
                            Image(systemName: "photo.badge.plus")
                                .font(.title2)
                            Text(L10n.Studio.addReferences).fontWeight(.medium)
                            Text(L10n.Studio.noReferences)
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
                            .disabled(referenceURLs.count >= 10)
                        }
                    }
                    .scrollIndicators(.hidden)

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
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(height: 230)
                    .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text(L10n.Studio.promptPlaceholder)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 18)
                            .allowsHitTesting(false)
                        }
                    }

                HStack(spacing: 10) {
                    Button(L10n.Studio.resetPrompts, systemImage: "arrow.counterclockwise") {
                        resetPrompts()
                    }
                    .disabled(prompt.isEmpty && negativePrompt.isEmpty)

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
                    SectionHeading(displayedPromptResult?.title ?? L10n.Studio.enhancedPrompt)
                    Spacer()
                    if let result = displayedPromptResult {
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

                ScrollView {
                    if let result = displayedPromptResult {
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

    private var modePromptGuidance: String {
        switch mode {
        case .create: L10n.Studio.guideCreate
        case .edit: L10n.Studio.guideEdit
        case .characterSheet: L10n.Studio.guideCharacter
        case .transparentAsset: L10n.Studio.guideTransparent
        }
    }

    private var presetCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(L10n.Studio.preset)
                Picker(L10n.Studio.preset, selection: $preset) {
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
            }
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

    private var displayedPromptResult: (title: String, value: String, copyHelp: String)? {
        guard let request = displayedPromptRequest else { return nil }
        if let enhancedPrompt = request.enhancedPrompt {
            return (L10n.Studio.enhancedPrompt, enhancedPrompt, L10n.Studio.copyEnhancedPrompt)
        }
        guard !request.enhancePrompt else { return nil }
        return (L10n.Studio.finalPrompt, request.prompt, L10n.Studio.copyFinalPrompt)
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
            Text(url.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Button(L10n.Studio.variation, systemImage: "square.on.square") {
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
                            Text(backend.name).tag(backend)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                }

                Text(appModel.generationBackend.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appModel.generationBackend == .diffusers {
                    HStack(spacing: 8) {
                        Toggle(L10n.Studio.viggleTurbo, isOn: $useViggleTurbo)
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
                }

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

                DisclosureGroup(L10n.Studio.advanced, isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(L10n.Studio.steps)
                            Spacer()
                            Text(useViggleTurbo && appModel.generationBackend == .diffusers ? "6" : "\(Int(steps))")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $steps, in: 10...50, step: 1)
                            .disabled(useViggleTurbo && appModel.generationBackend == .diffusers)

                        Toggle(L10n.Studio.randomSeed, isOn: $randomizeSeed)
                        if !randomizeSeed {
                            Stepper("\(L10n.Studio.seed): \(seed)", value: $seed, in: 0...Int(Int32.max))
                        }
                        Toggle(L10n.Studio.enhancePrompt, isOn: $enhancePrompt)
                            .disabled(appModel.generationBackend == .ggufQ6)
                        if appModel.generationBackend == .ggufQ6 {
                            Text(L10n.Studio.enhancerDiffusersOnly)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else if enhancePrompt && modelLibrary.state(for: .promptEnhancer) != .ready {
                            Text(L10n.Studio.enhancerInstallRequired)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        TextField(L10n.Studio.negativePlaceholder, text: $negativePrompt, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .disabled(useViggleTurbo && appModel.generationBackend == .diffusers)
                    }
                    .padding(.top, 12)
                }

                Divider()

                if !selectedModelIsReady {
                    Label(
                        useViggleTurbo && appModel.generationBackend == .diffusers
                            && modelLibrary.canGenerate(using: .diffusers)
                            && modelLibrary.state(for: .viggleTurbo) != .ready
                            ? L10n.Studio.viggleInstallRequired
                            : (enhancePrompt && appModel.generationBackend != .ggufQ6
                                && modelLibrary.state(for: .promptEnhancer) != .ready
                                ? L10n.Studio.enhancerInstallRequired : L10n.Studio.modelRequired),
                        systemImage: "exclamationmark.triangle"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if appModel.generationBackend != .ggufQ6,
                          case .failed = generation.state {
                    Label(L10n.Studio.runtimeRequired, systemImage: "gearshape.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                .disabled(
                    generation.state.isRunning ||
                    (selectedModelIsReady && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
                    (selectedModelIsReady && mode == .edit && referenceURLs.isEmpty) ||
                    (selectedModelIsReady && useViggleTurbo && appModel.generationBackend == .diffusers
                        && referenceURLs.count > 3) ||
                    (selectedModelIsReady && !customResolutionIsValid)
                )
            }
        }
    }

    private func chooseReferences() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }
        let availableSlots = max(0, 10 - referenceURLs.count)
        referenceURLs.append(contentsOf: panel.urls.prefix(availableSlots).filter { !referenceURLs.contains($0) })
        persistWorkspaceDraft()
    }

    @discardableResult
    private func persistWorkspaceDraft(persistPrompts: Bool = false) -> Bool {
        let previousRequest = projectStore.activeProject?.draft
            ?? projectStore.activeProject?.variants.max(by: { $0.createdAt < $1.createdAt })?.request
        let request = GenerationRequest(
            mode: mode,
            preset: preset,
            prompt: persistPrompts ? prompt : (previousRequest?.originalPrompt ?? previousRequest?.prompt ?? prompt),
            negativePrompt: persistPrompts ? negativePrompt : (previousRequest?.negativePrompt ?? negativePrompt),
            resolution: resolution,
            customWidth: resolution == .custom ? customWidth : nil,
            customHeight: resolution == .custom ? customHeight : nil,
            steps: useViggleTurbo && appModel.generationBackend == .diffusers ? 6 : Int(steps),
            seed: UInt32(seed),
            randomizeSeed: randomizeSeed,
            enhancePrompt: enhancePrompt,
            useViggleTurbo: useViggleTurbo && appModel.generationBackend == .diffusers,
            referenceImages: referenceURLs,
            maskImage: maskURL
        )
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

    private func openRequestedPrompt() {
        guard let id = appModel.promptToOpenID else { return }
        if let savedPrompt = projectStore.savedPrompts.first(where: { $0.id == id }) {
            prompt = savedPrompt.prompt
            negativePrompt = savedPrompt.negativePrompt
            promptsWereSaved = false
        }
        appModel.promptToOpenID = nil
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

    private func startGeneration(
        kind: ProjectVariant.Kind = .generation,
        parentID: UUID? = nil
    ) {
        refreshModelAvailability()
        let turboSelected = appModel.generationBackend == .diffusers && useViggleTurbo
        guard !turboSelected || referenceURLs.count <= 3 else {
            exportError = L10n.Studio.viggleMaxReferences
            return
        }
        let package = appModel.generationBackend.modelPackage
        guard modelLibrary.canGenerate(using: appModel.generationBackend),
              (!turboSelected || modelLibrary.state(for: .viggleTurbo) == .ready),
              (!enhancePrompt || appModel.generationBackend == .ggufQ6
                || modelLibrary.state(for: .promptEnhancer) == .ready),
              let modelRoot = modelLibrary.installationURL(for: package) else {
            appModel.selection = .models
            return
        }

        do {
            projectStore.configure(rootURL: storage.generationOutputURL)
            let outputDirectory = try projectStore.imagesDirectoryForActiveProject()
            let request = GenerationRequest(
                mode: mode,
                preset: preset,
                prompt: preset.applyingStyle(to: prompt.trimmingCharacters(in: .whitespacesAndNewlines)),
                originalPrompt: prompt,
                negativePrompt: negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
                resolution: resolution,
                customWidth: resolution == .custom ? customWidth : nil,
                customHeight: resolution == .custom ? customHeight : nil,
                steps: turboSelected ? 6 : Int(steps),
                seed: UInt32(seed),
                randomizeSeed: randomizeSeed,
                enhancePrompt: enhancePrompt,
                useViggleTurbo: turboSelected,
                referenceImages: referenceURLs,
                maskImage: maskURL
            )
            pendingVariantKind = kind
            pendingParentVariantID = parentID
            lastPersistedOutputURL = nil
            previewOverrideURL = nil
            previewRequest = request
            currentVariantID = nil
            evaluation = ImageEvaluation()
            previewHasTransparentPixels = nil
            generation.generate(
                request: request,
                modelRoot: modelRoot,
                promptEnhancerRoot: enhancePrompt && appModel.generationBackend != .ggufQ6
                    ? modelLibrary.installationURL(for: .promptEnhancer) : nil,
                outputDirectory: outputDirectory,
                backend: appModel.generationBackend
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
                parentID: pendingParentVariantID
            )
            currentVariantID = variant.id
            previewRequest = variant.request
            previewOverrideURL = projectStore.activeProject.map { projectStore.imageURL(for: variant, in: $0) }
            loadEvaluation(for: variant, imageURL: previewOverrideURL)
            lastPersistedOutputURL = url
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func upscale(_ source: URL, factor: Int) {
        guard let request = previewRequest ?? generation.record?.request else { return }
        isUpscaling = true
        Task {
            do {
                let directory = try projectStore.imagesDirectoryForActiveProject()
                let output = try await Self.upscaler.upscale(
                    source: source,
                    factor: factor,
                    outputDirectory: directory
                )
                let kind: ProjectVariant.Kind = factor == 2 ? .upscale2x : .upscale4x
                let variant = try projectStore.addVariant(
                    outputURL: output,
                    request: request,
                    kind: kind,
                    parentID: currentVariantID
                )
                currentVariantID = variant.id
                previewRequest = variant.request
                previewOverrideURL = output
                loadEvaluation(for: variant, imageURL: output)
            } catch {
                exportError = error.localizedDescription
            }
            isUpscaling = false
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
        } else {
            generation.resetPresentation()
            currentVariantID = nil
            previewRequest = nil
            previewOverrideURL = nil
            evaluation = ImageEvaluation()
            previewHasTransparentPixels = nil
        }
        mode = request.mode
        preset = request.preset
        prompt = restorePrompts ? (request.originalPrompt ?? request.prompt) : L10n.Studio.defaultPrompt
        negativePrompt = restorePrompts ? request.negativePrompt : ""
        promptsWereSaved = false
        resolution = request.resolution
        customWidth = request.customWidth ?? request.width
        customHeight = request.customHeight ?? request.height
        steps = request.useViggleTurbo == true ? Double(request.preset.steps) : Double(request.steps)
        seed = Int(request.seed)
        randomizeSeed = request.randomizeSeed
        enhancePrompt = appModel.generationBackend != .ggufQ6 && request.enhancePrompt
        useViggleTurbo = request.useViggleTurbo == true
        referenceURLs = request.referenceImages
        maskURL = request.maskImage
    }

    private func clearWorkspace() {
        generation.resetPresentation()
        previewOverrideURL = nil
        previewRequest = nil
        currentVariantID = nil
        evaluation = ImageEvaluation()
        previewHasTransparentPixels = nil
        maskURL = nil
        referenceURLs = []
        prompt = L10n.Studio.defaultPrompt
        negativePrompt = ""
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
            && (appModel.generationBackend != .diffusers || !useViggleTurbo
                || modelLibrary.state(for: .viggleTurbo) == .ready)
            && (!enhancePrompt || appModel.generationBackend == .ggufQ6
                || modelLibrary.state(for: .promptEnhancer) == .ready)
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
            set: { projectStore.activeProjectID = $0 }
        )
    }

    private var customResolutionIsValid: Bool {
        resolution != .custom || (
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
