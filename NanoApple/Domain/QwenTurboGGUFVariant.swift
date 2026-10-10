// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

enum QwenTurboGGUFVariant: Sendable {
    case q8, atomicQ5

    var diffusionFile: String {
        switch self {
        case .q8: "Qwen-Image-2.1-Turbo-Q8_0.gguf"
        case .atomicQ5: "Qwen-Image-2.1-Turbo-AD-Q5_K.gguf"
        }
    }
    var textEncoderFile: String {
        "text_encoders/Qwen3VL-8B-Instruct-\(self == .q8 ? "Q8_0" : "Q4_K_M").gguf"
    }
    var visionEncoderFile: String { "text_encoders/mmproj-Qwen3VL-8B-Instruct-Q8_0.gguf" }
    var vaeFile: String { "vae/qwen_image_2.1_vae_bf16.safetensors" }
    var requiredFiles: [String] { [diffusionFile, textEncoderFile, visionEncoderFile, vaeFile] }
    static let samplingSigmas = "1.0,0.978453,0.95418,0.926626,0.89508,0.845148,0.704534,0.414568,0.0"

    func arguments(request: GenerationRequest, modelRoot: URL, outputURL: URL,
                   reducedMemory: Bool) -> [String] {
        var prompt = request.enhancedPrompt ?? request.prompt
        if request.mode.requestsTransparency {
            prompt = "This is an RGBA image with transparency. " + prompt + " The image has alpha channel and the background is transparent."
        }
        var result = [
            "--diffusion-model", modelRoot.appending(path: diffusionFile).path,
            "--llm", modelRoot.appending(path: textEncoderFile).path,
            "--vae", modelRoot.appending(path: vaeFile).path,
            "--prompt", prompt, "--output", outputURL.path,
            "--width", String(request.width), "--height", String(request.height),
            "--steps", "8", "--seed", request.randomizeSeed ? "-1" : String(request.seed),
            "--cfg-scale", "1.0", "--sampling-method", "euler",
            "--flow-shift", "1", "--sigmas", Self.samplingSigmas,
            "--rng", "cpu", "--diffusion-fa", "--offload-to-cpu", "--mmap",
            "--log-level", "info"
        ]
        if reducedMemory { result += ["--vae-tiling", "--max-vram", "-4"] }
        if !request.referenceImages.isEmpty {
            result += ["--llm_vision", modelRoot.appending(path: visionEncoderFile).path]
            for reference in request.referenceImages { result += ["--ref-image", reference.path] }
            result += ["--ref-image-args", "preset=qwen,ref_index_mode=increase"]
        }
        if let mask = request.maskImage, let source = request.referenceImages.first {
            result += ["--init-img", source.path, "--mask", mask.path, "--strength", "1.0"]
        }
        return result
    }
}
