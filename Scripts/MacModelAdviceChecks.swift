// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

@main
struct MacModelAdviceChecks {
    static func profile(_ memory: Int, chip: String = "Apple M2 Max", arm: Bool = true,
                        metal: Bool = true, os: Int = 14) -> MacHardwareProfile {
        MacHardwareProfile(chipName: chip, memoryBytes: UInt64(memory) * 1_024 * 1_024 * 1_024,
                           cpuCores: 12, isAppleSilicon: arm, hasMetal: metal, macOSMajorVersion: os)
    }
    static func main() throws {
        let turbo: [GenerationBackend] = [.diffusersTurbo, .ggufTurboQ8, .ggufTurboAtomicQ5]
        for incompatible in [profile(64, arm: false), profile(64, metal: false), profile(64, os: 13)] {
            for backend in GenerationBackend.allCases {
                precondition(ModelAdvice.assess(backend, on: incompatible).rating == .incompatible)
            }
        }
        for memory in [8, 16] {
            for backend in turbo {
                precondition(ModelAdvice.assess(backend, on: profile(memory)).rating == .conditional)
            }
        }
        precondition(ModelAdvice.assess(.diffusersTurbo, on: profile(63)).rating == .conditional)
        precondition(ModelAdvice.assess(.diffusersTurbo, on: profile(64)).rating == .recommended)
        precondition(ModelAdvice.assess(.ggufTurboQ8, on: profile(31)).rating == .conditional)
        precondition(ModelAdvice.assess(.ggufTurboQ8, on: profile(32)).rating == .recommended)
        precondition(ModelAdvice.assess(.ggufTurboAtomicQ5, on: profile(23, chip: "Apple M2")).rating == .conditional)
        precondition(ModelAdvice.assess(.ggufTurboAtomicQ5, on: profile(24, chip: "Apple M2")).rating == .recommended)
        precondition(ModelAdvice.preferredTurbo(on: profile(64)) == .diffusersTurbo)
        precondition(ModelAdvice.preferredTurbo(on: profile(32)) == .ggufTurboQ8)
        precondition(ModelAdvice.preferredTurbo(on: profile(24, chip: "Apple M2")) == .ggufTurboAtomicQ5)
        precondition(ModelAdvice.assess(.ggufTurboQ8, on: profile(32, chip: "Apple M4")).rating == .conditional)
        precondition(ModelAdvice.assess(.ggufTurboQ8, on: profile(32), width: 2048, height: 2048).rating == .conditional)
        precondition(ModelAdvice.assess(.ggufTurboQ8, on: profile(64), width: 2048, height: 2048).rating == .recommended)
        let request = GenerationRequest(mode: .edit, preset: .none, prompt: "edit",
            enhancedPrompt: "prepared instruction", negativePrompt: "should be ignored",
            resolution: .square, steps: 30, seed: 42, randomizeSeed: false,
            enhancePrompt: true, referenceImages: [URL(fileURLWithPath: "/test/reference with spaces.png")],
            maskImage: nil)
        for variant in [QwenTurboGGUFVariant.q8, .atomicQ5] {
            let arguments = variant.arguments(request: request, modelRoot: URL(fileURLWithPath: "/test/models"),
                                              outputURL: URL(fileURLWithPath: "/test/output.png"), reducedMemory: true)
            func value(_ key: String) -> String { arguments[arguments.firstIndex(of: key)! + 1] }
            precondition(value("--steps") == "8" && value("--cfg-scale") == "1.0")
            precondition(value("--flow-shift") == "1")
            let sigmas = value("--sigmas").split(separator: ",").compactMap { Double($0) }
            precondition(sigmas.count == 9 && sigmas.first == 1 && sigmas.last == 0)
            precondition(zip(sigmas, sigmas.dropFirst()).allSatisfy { $0 > $1 })
            precondition(value("--prompt") == "prepared instruction")
            precondition(value("--ref-image") == "/test/reference with spaces.png")
            precondition(value("--diffusion-model").hasSuffix(variant.diffusionFile))
            precondition(value("--llm").hasSuffix(variant.textEncoderFile))
            precondition(!arguments.contains("--negative-prompt"))
            precondition(!arguments.contains("--stream-layers"))
            precondition(arguments.contains("--vae-tiling") && value("--max-vram") == "-4")
            var transparent = request
            transparent.mode = .transparentAsset
            transparent.referenceImages = []
            let transparentArgs = variant.arguments(request: transparent, modelRoot: URL(fileURLWithPath: "/test/models"),
                                                     outputURL: URL(fileURLWithPath: "/test/output.png"), reducedMemory: false)
            precondition(transparentArgs.contains { $0.contains("RGBA image with transparency") })
            precondition(!transparentArgs.contains("--llm_vision"))
            precondition(!transparentArgs.contains("--max-vram"))
        }
        print("Hardware compatibility, RAM boundaries, chip tiers, canvas advice and GGUF commands passed")
        print(MacHardwareProfile.current.summary)
        print("Suggested: \(ModelAdvice.preferredTurbo().name)")
    }
}
