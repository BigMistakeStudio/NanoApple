// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

@main
struct TurboBackendChecks {
    static func main() throws {
        precondition(GenerationBackend.allCases.map(\.rawValue) == ["diffusers", "diffusersHeretic", "diffusersTurbo", "ggufTurboQ8", "ggufTurboAtomicQ5"])
        let old = try JSONDecoder().decode(GenerationBackend.self, from: Data("\"ggufQ6\"".utf8))
        precondition(old == .diffusersTurbo)
        precondition(GenerationBackend.restored(from: "ggufQ6") == .diffusersTurbo)
        precondition(old.fixedStepCount == 8 && !old.supportsNegativePrompt)
        precondition(old.requiredPackages == [.qwenImage21Turbo])
        precondition(old.modelPackage.repositories.map(\.id) == ["Qwen/Qwen-Image-2.1-Turbo"])
        for backend in [GenerationBackend.ggufTurboQ8, .ggufTurboAtomicQ5] {
            precondition(backend.fixedStepCount == 8 && !backend.supportsNegativePrompt)
            precondition(backend.requiredPackages.count == 1)
            precondition(ModelPackage.supportedPackages.contains(backend.modelPackage))
            precondition(backend.modelPackage.repositories.count == 3)
        }
        let data = try JSONEncoder().encode(old)
        let restored = try JSONDecoder().decode(GenerationBackend.self, from: data)
        precondition(restored == .diffusersTurbo)
        print("Turbo choices, package routing and legacy migration passed")
    }
}
