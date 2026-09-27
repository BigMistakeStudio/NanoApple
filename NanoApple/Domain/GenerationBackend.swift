import Foundation

enum GenerationBackend: String, CaseIterable, Codable, Identifiable, Sendable {
    case diffusers
    case diffusersHeretic
    case ggufQ6

    var id: String { rawValue }

    var name: String {
        switch self {
        case .diffusers:
            String(localized: "engine.diffusers.name", defaultValue: "Qwen-Image 2.1 · Complet")
        case .diffusersHeretic:
            String(localized: "engine.heretic.name", defaultValue: "Qwen-Image 2.1 · Heretic")
        case .ggufQ6:
            String(localized: "engine.gguf_q6.name", defaultValue: "Qwen-Image 2.1 · GGUF Q6")
        }
    }

    var detail: String {
        switch self {
        case .diffusers:
            String(localized: "engine.diffusers.detail", defaultValue: "Poids officiels complets · environ 33,1 Go")
        case .diffusersHeretic:
            String(localized: "engine.heretic.detail", defaultValue: "Modèle complet avec encodeur Heretic · environ 17,5 Go supplémentaires")
        case .ggufQ6:
            String(localized: "engine.gguf_q6.detail", defaultValue: "Version quantifiée plus compacte · environ 12,3 Go")
        }
    }

    var modelPackage: ModelPackage {
        switch self {
        case .diffusers, .diffusersHeretic: .qwenImage21
        case .ggufQ6: .qwenImage21GGUFQ6
        }
    }

    var requiredPackages: [ModelPackage] {
        switch self {
        case .diffusers: [.qwenImage21]
        case .diffusersHeretic: [.qwenImage21, .qwenImage21HereticEncoder]
        case .ggufQ6: [.qwenImage21GGUFQ6]
        }
    }
}
