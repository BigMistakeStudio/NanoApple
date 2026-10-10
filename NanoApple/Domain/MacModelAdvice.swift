// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Metal
import Darwin

struct MacHardwareProfile: Sendable {
    enum ChipTier: Sendable { case standard, pro, max, ultra, unknown }

    let chipName: String
    let memoryBytes: UInt64
    let cpuCores: Int
    let isAppleSilicon: Bool
    let hasMetal: Bool
    let macOSMajorVersion: Int

    var memoryGiB: Int { Int(memoryBytes / (1_024 * 1_024 * 1_024)) }
    var chipTier: ChipTier {
        let name = chipName.lowercased()
        if name.contains("ultra") { return .ultra }
        if name.contains("max") { return .max }
        if name.contains("pro") { return .pro }
        if name.contains("apple m") { return .standard }
        return .unknown
    }
    var hasHighPerformanceChip: Bool { [.pro, .max, .ultra].contains(chipTier) }
    var summary: String { String(localized: "advice.hardware.summary", defaultValue: "\(chipName) · \(memoryGiB) Go de mémoire · \(cpuCores) cœurs CPU") }

    static let current: MacHardwareProfile = {
        var size = 0
        var name = "Mac"
        if sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 {
                name = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
        var arm64: Int32 = 0
        var armSize = MemoryLayout<Int32>.size
        _ = sysctlbyname("hw.optional.arm64", &arm64, &armSize, nil, 0)
        return MacHardwareProfile(chipName: name,
                                  memoryBytes: ProcessInfo.processInfo.physicalMemory,
                                  cpuCores: ProcessInfo.processInfo.processorCount,
                                  isAppleSilicon: arm64 == 1,
                                  hasMetal: MTLCreateSystemDefaultDevice() != nil,
                                  macOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }()
}

struct ModelAdvice: Sendable {
    enum Rating: Sendable {
        case recommended, conditional, incompatible
        var title: String {
            switch self {
            case .recommended: String(localized: "advice.recommended", defaultValue: "Recommandé")
            case .conditional: String(localized: "advice.conditional", defaultValue: "Sous réserve")
            case .incompatible: String(localized: "advice.incompatible", defaultValue: "Ne fonctionnera pas")
            }
        }
        var symbol: String {
            switch self {
            case .recommended: "checkmark.circle.fill"
            case .conditional: "exclamationmark.triangle.fill"
            case .incompatible: "xmark.circle.fill"
            }
        }
    }
    let rating: Rating
    let reason: String

    static func assess(_ backend: GenerationBackend, on mac: MacHardwareProfile = .current,
                       width: Int = 1024, height: Int = 1024) -> ModelAdvice {
        guard mac.isAppleSilicon, mac.hasMetal, mac.macOSMajorVersion >= 14 else {
            return ModelAdvice(rating: .incompatible,
                               reason: String(localized: "advice.unsupported_mac", defaultValue: "NanoApple demande un Mac Apple Silicon avec Metal et macOS 14 ou ultérieur."))
        }
        let comfortableRAM: Int
        switch backend {
        case .diffusers, .diffusersHeretic, .diffusersTurbo: comfortableRAM = 64
        case .ggufTurboQ8: comfortableRAM = 32
        case .ggufTurboAtomicQ5: comfortableRAM = 24
        }
        guard mac.memoryGiB >= comfortableRAM else {
            return ModelAdvice(rating: .conditional,
                               reason: String(localized: "advice.low_memory", defaultValue: "\(mac.memoryGiB) Go détectés ; \(comfortableRAM) Go conseillés. Commencez à 768 px, fermez les autres applications ; ralentissements ou manque de mémoire possibles."))
        }
        let largeCanvas = Int64(width) * Int64(height) > 1_500_000
        if largeCanvas && mac.memoryGiB < comfortableRAM + 32 {
            return ModelAdvice(rating: .conditional,
                               reason: String(localized: "advice.large_canvas", defaultValue: "Ce grand format augmente fortement la mémoire et le temps de calcul. Essayez d’abord un format proche de 1024 px."))
        }
        if backend != .ggufTurboAtomicQ5 && !mac.hasHighPerformanceChip {
            return ModelAdvice(rating: .conditional,
                               reason: String(localized: "advice.slower_chip", defaultValue: "Mémoire suffisante, mais une puce Pro, Max ou Ultra est conseillée pour ce modèle. La génération peut être lente sur cette puce."))
        }
        return ModelAdvice(rating: .recommended,
                           reason: largeCanvas
                            ? String(localized: "advice.ready.large", defaultValue: "Mémoire et puce adaptées pour démarrer avec ce format. Le temps réel dépend de la génération et des applications ouvertes.")
                            : String(localized: "advice.ready.standard", defaultValue: "Mémoire et puce adaptées pour démarrer autour de 1024 px. Le temps réel dépend de la génération et des applications ouvertes."))
    }

    static func preferredTurbo(on mac: MacHardwareProfile = .current) -> GenerationBackend {
        if assess(.diffusersTurbo, on: mac).rating == .recommended { return .diffusersTurbo }
        if assess(.ggufTurboQ8, on: mac).rating == .recommended { return .ggufTurboQ8 }
        return .ggufTurboAtomicQ5
    }
}
