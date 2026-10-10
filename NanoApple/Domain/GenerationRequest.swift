// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

struct GenerationRequest: Identifiable, Codable, Sendable {
    var id = UUID()
    var createdAt = Date()
    var mode: GenerationMode
    var preset: GenerationPreset
    var prompt: String
    // Keep the user's exact instruction and the model rewrite alongside the prepared prompt.
    // Optional fields preserve decoding of projects created before prompt enhancement worked.
    var originalPrompt: String? = nil
    var enhancedPrompt: String? = nil
    var negativePrompt: String
    var resolution: CanvasResolution
    var customWidth: Int?
    var customHeight: Int?
    var steps: Int
    var seed: UInt32
    var randomizeSeed: Bool
    var enhancePrompt: Bool
    // Optional so projects saved before Viggle Turbo existed still decode.
    var useViggleTurbo: Bool? = nil
    // Optional so projects created before Consistency LoRA remain decodable.
    var useConsistencyLoRA: Bool? = nil
    // Optional to preserve decoding of existing project manifests.
    var viewpointOrbit: ViewpointOrbitSettings? = nil
    // Older variants did not record the engine; keep their manifests decodable.
    var backend: GenerationBackend? = nil
    var referenceImages: [URL]
    var maskImage: URL?

    var width: Int {
        resolution == .custom ? (customWidth ?? resolution.width) : resolution.width
    }

    var height: Int {
        resolution == .custom ? (customHeight ?? resolution.height) : resolution.height
    }

    mutating func configureViewpointOrbit(_ settings: ViewpointOrbitSettings) {
        mode = .viewpointOrbit
        viewpointOrbit = settings
        preset = .none
        prompt = settings.prompt
        originalPrompt = settings.prompt
        enhancedPrompt = nil
        negativePrompt = ""
        resolution = .custom
        customWidth = 768
        customHeight = 768
        steps = 40
        enhancePrompt = false
        useViggleTurbo = false
        useConsistencyLoRA = false
        maskImage = nil
    }

}

struct SavedPrompt: Identifiable, Codable, Sendable {
    var id = UUID()
    var savedAt = Date()
    var prompt: String
    var negativePrompt: String
}

struct PromptHistoryEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let createdAt: Date
    let projectName: String
    let originalPrompt: String
    let enhancedPrompt: String?
    let usedPrompt: String
    let negativePrompt: String

    init(request: GenerationRequest, createdAt: Date, projectName: String) {
        id = request.id
        self.createdAt = createdAt
        self.projectName = projectName
        originalPrompt = request.originalPrompt ?? request.prompt
        enhancedPrompt = request.enhancedPrompt
        usedPrompt = request.enhancedPrompt ?? request.prompt
        negativePrompt = request.negativePrompt
    }
}

struct CreationRecord: Identifiable, Codable, Sendable {
    enum Status: String, Codable, Sendable {
        case queued
        case preparing
        case generating
        case completed
        case failed
        case cancelled
    }

    var id = UUID()
    var request: GenerationRequest
    var status: Status = .queued
    var progress: Double = 0
    var outputURL: URL?
    var errorDescription: String?
    var contentSafety: ContentSafetyAssessment?
}

struct CharacterProfile: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var summary: String
    var preserve: String
    var referenceImages: [URL] = []
}
