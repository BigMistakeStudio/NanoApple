// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

@MainActor
final class GenerationCoordinator: ObservableObject {
    enum State: Equatable {
        case idle
        case switchingEngine
        case preparing
        case enhancingPrompt
        case generating(Double)
        case screeningContent
        case completed(URL)
        case failed(String)
        case cancelled

        var isRunning: Bool {
            switch self {
            case .switchingEngine, .preparing, .enhancingPrompt, .generating, .screeningContent: true
            default: false
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var record: CreationRecord?
    @Published private(set) var generatingStartedAt: Date?

    private let diffusersEngine: any ImageGenerationEngine
    private let hereticDiffusersEngine: any ImageGenerationEngine
    private let turboDiffusersEngine: any ImageGenerationEngine
    private let turboQ8Engine: any ImageGenerationEngine
    private let turboAtomicEngine: any ImageGenerationEngine
    private let promptEnhancer = PromptEnhancer()
    private let previewPromptEnhancer = PromptEnhancer()
    private let nsfwClassifier = NSFWClassifier()
    private var activeEngine: (any ImageGenerationEngine)?
    private var task: Task<Void, Never>?
    private var preparedBackend: GenerationBackend?
    private var currentRunID: UUID?
    private var currentSwitchID: UUID?

    init(
        diffusersEngine: any ImageGenerationEngine = QwenPythonGenerationEngine(),
        hereticDiffusersEngine: any ImageGenerationEngine = QwenPythonGenerationEngine(
            textEncoderPackageID: ModelPackage.qwenImage21HereticEncoder.id
        ),
        turboDiffusersEngine: any ImageGenerationEngine = QwenPythonGenerationEngine(officialTurbo: true),
        turboQ8Engine: any ImageGenerationEngine = QwenGGUFGenerationEngine(variant: .q8),
        turboAtomicEngine: any ImageGenerationEngine = QwenGGUFGenerationEngine(variant: .atomicQ5)
    ) {
        self.diffusersEngine = diffusersEngine
        self.hereticDiffusersEngine = hereticDiffusersEngine
        self.turboDiffusersEngine = turboDiffusersEngine
        self.turboQ8Engine = turboQ8Engine
        self.turboAtomicEngine = turboAtomicEngine
    }

    func generate(
        request: GenerationRequest,
        modelRoot: URL,
        promptEnhancerRoot: URL?,
        outputDirectory: URL,
        backend: GenerationBackend,
        safetyFilterEnabled: Bool,
        safetyModelRoot: URL?
    ) {
        guard task == nil else { return }
        guard backend.advice.rating != .incompatible else {
            report(error: ImageGenerationError.unsupportedConfiguration)
            return
        }
        guard request.mode != .viewpointOrbit || backend == .diffusers else {
            report(error: ImageGenerationError.unsupportedConfiguration)
            return
        }
        guard !safetyFilterEnabled || safetyModelRoot != nil else {
            report(error: ImageGenerationError.nsfwClassifierNotInstalled)
            return
        }
        generatingStartedAt = nil

        let engine: any ImageGenerationEngine = switch backend {
        case .diffusers: diffusersEngine
        case .diffusersHeretic: hereticDiffusersEngine
        case .diffusersTurbo: turboDiffusersEngine
        case .ggufTurboQ8: turboQ8Engine
        case .ggufTurboAtomicQ5: turboAtomicEngine
        }
        let runID = UUID()
        currentRunID = runID

        var request = request
        request.backend = backend
        if backend.isTurbo {
            request.steps = 8
            request.negativePrompt = ""
            request.useViggleTurbo = false
            request.useConsistencyLoRA = false
        }
        var creation = CreationRecord(request: request)
        creation.status = preparedBackend == backend ? .preparing : .queued
        record = creation
        state = preparedBackend == backend ? .preparing : .switchingEngine

        task = Task { [weak self] in
            guard let self else { return }
            do {
                if preparedBackend != backend {
                    await unloadAllEngines()
                    try Task.checkCancellation()
                    guard currentRunID == runID else { return }
                    preparedBackend = backend
                }

                activeEngine = engine
                record?.status = .preparing
                state = .preparing
                try await engine.prepare(modelRoot: modelRoot)
                try Task.checkCancellation()
                guard currentRunID == runID else { return }
                var preparedRequest = request
                if request.mode != .viewpointOrbit && request.enhancePrompt
                    && request.enhancedPrompt == nil {
                    guard let promptEnhancerRoot else {
                        throw ImageGenerationError.promptEnhancerNotInstalled
                    }
                    state = .enhancingPrompt
                    preparedRequest.enhancedPrompt = try await promptEnhancer.enhance(
                        request: request,
                        modelRoot: promptEnhancerRoot,
                        runtimeModelRoot: modelRoot,
                        outputDirectory: outputDirectory
                    )
                    try Task.checkCancellation()
                    guard currentRunID == runID else { return }
                    record?.request = preparedRequest
                }
                record?.status = .generating
                generatingStartedAt = Date()
                state = .generating(0)
                let output = try await engine.generate(
                    request: preparedRequest,
                    outputDirectory: outputDirectory
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.update(progress: progress, runID: runID)
                    }
                }
                guard currentRunID == runID else { return }
                if safetyFilterEnabled, let safetyModelRoot {
                    state = .screeningContent
                    do {
                        let score = try await nsfwClassifier.classify(
                            imageURL: output,
                            modelRoot: safetyModelRoot,
                            runtimeModelRoot: modelRoot,
                            outputDirectory: outputDirectory
                        )
                        record?.contentSafety = ContentSafetyAssessment(nsfwProbability: score)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        record?.contentSafety = .unavailable
                        await AppLog.shared.append(.error, category: "ContentSafety", error.localizedDescription)
                    }
                    try Task.checkCancellation()
                }
                guard currentRunID == runID else { return }
                record?.status = .completed
                record?.progress = 1
                record?.outputURL = output
                state = .completed(output)
            } catch is CancellationError {
                if currentRunID == runID {
                    record?.status = .cancelled
                    state = .cancelled
                }
            } catch {
                if currentRunID == runID {
                    record?.status = .failed
                    record?.errorDescription = error.localizedDescription
                    state = .failed(error.localizedDescription)
                }
            }
            if currentRunID == runID {
                activeEngine = nil
                currentRunID = nil
                task = nil
            }
        }
    }

    func preparePrompt(
        request: GenerationRequest,
        modelRoot: URL,
        runtimeModelRoot: URL,
        outputDirectory: URL
    ) async throws -> String {
        guard !state.isRunning, request.mode != .viewpointOrbit else {
            throw ImageGenerationError.unsupportedConfiguration
        }
        return try await previewPromptEnhancer.enhance(
            request: request,
            modelRoot: modelRoot,
            runtimeModelRoot: runtimeModelRoot,
            outputDirectory: outputDirectory
        )
    }

    func switchBackend(to backend: GenerationBackend) async {
        guard preparedBackend != backend else { return }

        let switchID = UUID()
        currentSwitchID = switchID
        state = .switchingEngine

        let runningTask = task
        currentRunID = nil
        runningTask?.cancel()
        await promptEnhancer.cancel()
        await nsfwClassifier.cancel()
        if let activeEngine {
            await activeEngine.cancel()
        }
        await runningTask?.value

        guard currentSwitchID == switchID else { return }
        task = nil
        activeEngine = nil
        await unloadAllEngines()

        guard currentSwitchID == switchID else { return }
        preparedBackend = backend
        record = nil
        generatingStartedAt = nil
        state = .idle
        await AppLog.shared.append(category: "Generation", "Modèle actif : \(backend.name).")
    }

    func cancel() {
        task?.cancel()
        Task { await promptEnhancer.cancel() }
        Task { await nsfwClassifier.cancel() }
        if let activeEngine {
            Task { await activeEngine.cancel() }
        }
    }

    func report(error: Error) {
        record?.status = .failed
        record?.errorDescription = error.localizedDescription
        state = .failed(error.localizedDescription)
    }

    func resetPresentation() {
        guard !state.isRunning else { return }
        record = nil
        generatingStartedAt = nil
        state = .idle
    }

    private func unloadAllEngines() async {
        await diffusersEngine.unload()
        await hereticDiffusersEngine.unload()
        await turboDiffusersEngine.unload()
        await turboQ8Engine.unload()
        await turboAtomicEngine.unload()
    }

    private func update(progress: Double, runID: UUID) {
        guard currentRunID == runID else { return }
        let value = min(max(progress, 0), 1)
        record?.progress = value
        state = .generating(value)
    }
}
