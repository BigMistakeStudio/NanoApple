import Foundation

@MainActor
final class GenerationCoordinator: ObservableObject {
    enum State: Equatable {
        case idle
        case switchingEngine
        case preparing
        case enhancingPrompt
        case generating(Double)
        case completed(URL)
        case failed(String)
        case cancelled

        var isRunning: Bool {
            switch self {
            case .switchingEngine, .preparing, .enhancingPrompt, .generating: true
            default: false
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var record: CreationRecord?

    private let diffusersEngine: any ImageGenerationEngine
    private let hereticDiffusersEngine: any ImageGenerationEngine
    private let ggufEngine: any ImageGenerationEngine
    private let promptEnhancer = PromptEnhancer()
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
        ggufEngine: any ImageGenerationEngine = QwenGGUFGenerationEngine()
    ) {
        self.diffusersEngine = diffusersEngine
        self.hereticDiffusersEngine = hereticDiffusersEngine
        self.ggufEngine = ggufEngine
    }

    func generate(
        request: GenerationRequest,
        modelRoot: URL,
        promptEnhancerRoot: URL?,
        outputDirectory: URL,
        backend: GenerationBackend
    ) {
        guard task == nil else { return }

        let engine: any ImageGenerationEngine = switch backend {
        case .diffusers: diffusersEngine
        case .diffusersHeretic: hereticDiffusersEngine
        case .ggufQ6: ggufEngine
        }
        let runID = UUID()
        currentRunID = runID

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
                if request.enhancePrompt && backend != .ggufQ6 {
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

    func switchBackend(to backend: GenerationBackend) async {
        guard preparedBackend != backend || task != nil else { return }

        let switchID = UUID()
        currentSwitchID = switchID
        state = .switchingEngine

        let runningTask = task
        currentRunID = nil
        runningTask?.cancel()
        await promptEnhancer.cancel()
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
        state = .idle
        await AppLog.shared.append(category: "Generation", "Modèle actif : \(backend.name).")
    }

    func cancel() {
        task?.cancel()
        Task { await promptEnhancer.cancel() }
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
        state = .idle
    }

    private func unloadAllEngines() async {
        await diffusersEngine.unload()
        await hereticDiffusersEngine.unload()
        await ggufEngine.unload()
    }

    private func update(progress: Double, runID: UUID) {
        guard currentRunID == runID else { return }
        let value = min(max(progress, 0), 1)
        record?.progress = value
        state = .generating(value)
    }
}
