// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

enum GenerationBackend: String, CaseIterable, Codable, Identifiable, Sendable {
    case diffusers
    case diffusersHeretic
    case diffusersTurbo
    case ggufTurboQ8
    case ggufTurboAtomicQ5

    var id: String { rawValue }

    static func restored(from rawValue: String) -> GenerationBackend? {
        rawValue == "ggufQ6" ? .diffusersTurbo : Self(rawValue: rawValue)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let backend = Self.restored(from: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown generation backend: \(value)")
        }
        self = backend
    }

    var isTurbo: Bool { self == .diffusersTurbo || isGGUF }
    var isGGUF: Bool { self == .ggufTurboQ8 || self == .ggufTurboAtomicQ5 }
    var fixedStepCount: Int? { isTurbo ? 8 : nil }
    var supportsNegativePrompt: Bool { !isTurbo }
    var advice: ModelAdvice { ModelAdvice.assess(self) }
    var choiceTitle: String { "\(name) · \(advice.rating.title)" }

    var name: String {
        switch self {
        case .diffusers:
            String(localized: "engine.diffusers.name", defaultValue: "Qwen-Image 2.1 · Complet")
        case .diffusersHeretic:
            String(localized: "engine.heretic.name", defaultValue: "Qwen-Image 2.1 · Heretic")
        case .diffusersTurbo:
            String(localized: "engine.turbo.name", defaultValue: "Turbo · Officiel complet")
        case .ggufTurboQ8: String(localized: "engine.turbo.q8.name", defaultValue: "Turbo · GGUF Q8 · 7,6 Go")
        case .ggufTurboAtomicQ5: String(localized: "engine.turbo.atomic.name", defaultValue: "Turbo · AtomicChat Q5 · 5,4 Go")
        }
    }

    var detail: String {
        switch self {
        case .diffusers:
            String(localized: "engine.diffusers.detail", defaultValue: "Poids officiels complets · environ 33,1 Go")
        case .diffusersHeretic:
            String(localized: "engine.heretic.detail", defaultValue: "Modèle complet avec encodeur Heretic · environ 17,5 Go supplémentaires")
        case .diffusersTurbo:
            String(localized: "engine.turbo.detail", defaultValue: "Précision complète · 8 étapes · paquet de 32,5 Go")
        case .ggufTurboQ8: String(localized: "engine.turbo.q8.detail", defaultValue: "Fidélité élevée · générateur 7,6 Go · paquet complet 17,7 Go")
        case .ggufTurboAtomicQ5: String(localized: "engine.turbo.atomic.detail", defaultValue: "Mémoire réduite · générateur 5,4 Go · paquet complet 11,9 Go · détails moins fidèles")
        }
    }

    var modelPackage: ModelPackage {
        switch self {
        case .diffusers, .diffusersHeretic: .qwenImage21
        case .diffusersTurbo: .qwenImage21Turbo
        case .ggufTurboQ8: .qwenImage21TurboQ8
        case .ggufTurboAtomicQ5: .qwenImage21TurboAtomicQ5
        }
    }

    var requiredPackages: [ModelPackage] {
        switch self {
        case .diffusers: [.qwenImage21]
        case .diffusersHeretic: [.qwenImage21, .qwenImage21HereticEncoder]
        case .diffusersTurbo: [.qwenImage21Turbo]
        case .ggufTurboQ8: [.qwenImage21TurboQ8]
        case .ggufTurboAtomicQ5: [.qwenImage21TurboAtomicQ5]
        }
    }
}
