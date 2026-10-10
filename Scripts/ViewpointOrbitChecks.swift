// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

// Compile with NanoApple/Domain/*.swift, then pass the emitted JSON to
// test_viewpoint_orbit.py to validate the wire contract in both languages.
@main
struct ViewpointOrbitChecks {
    static func main() throws {
        let original = GenerationRequest(
            mode: .edit, preset: .none, prompt: "Keep this old instruction",
            enhancedPrompt: "A rewrite", negativePrompt: "blur",
            resolution: .square, steps: 6, seed: 42, randomizeSeed: false,
            enhancePrompt: true, useViggleTurbo: true, useConsistencyLoRA: true,
            backend: .diffusers, referenceImages: [URL(fileURLWithPath: "/tmp/subject.png")],
            maskImage: URL(fileURLWithPath: "/tmp/mask.png")
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        // An actual legacy manifest has no Orbit field at all.
        var legacy = try JSONSerialization.jsonObject(with: encoder.encode(original)) as! [String: Any]
        legacy.removeValue(forKey: "viewpointOrbit")
        let oldRequest = try decoder.decode(GenerationRequest.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(oldRequest.viewpointOrbit == nil && oldRequest.mode == .edit)
        precondition(oldRequest.prompt == original.prompt)

        var requests: [GenerationRequest] = []
        for rotation in ViewpointOrbitSettings.Rotation.allCases {
            for elevation in ViewpointOrbitSettings.Elevation.allCases {
                let settings = ViewpointOrbitSettings(rotation: rotation, elevation: elevation)
                if !settings.isValid { continue }
                var request = original
                request.configureViewpointOrbit(settings)
                let saved = try decoder.decode(GenerationRequest.self, from: encoder.encode(request))
                precondition(saved.viewpointOrbit == settings && saved.mode.requestsTransparency)
                precondition(saved.width == 768 && saved.height == 768 && saved.steps == 40)
                precondition(saved.preset == .none && saved.prompt == settings.prompt)
                precondition(saved.enhancedPrompt == nil && !saved.enhancePrompt && saved.negativePrompt.isEmpty)
                precondition(saved.useViggleTurbo == false && saved.useConsistencyLoRA == false)
                precondition(saved.maskImage == nil && saved.referenceImages == original.referenceImages)
                requests.append(saved)
            }
        }
        precondition(requests.count == 23)
        precondition(ModelPackage.supportedPackages.contains { $0.id == ModelPackage.viewpointOrbit.id })
        precondition(!ModelPackage.defaultPackages.contains { $0.id == ModelPackage.viewpointOrbit.id })
        FileHandle.standardOutput.write(try encoder.encode(requests))
    }
}
