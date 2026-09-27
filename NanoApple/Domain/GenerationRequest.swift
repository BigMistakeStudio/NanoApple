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
    var referenceImages: [URL]
    var maskImage: URL?

    var width: Int {
        resolution == .custom ? (customWidth ?? resolution.width) : resolution.width
    }

    var height: Int {
        resolution == .custom ? (customHeight ?? resolution.height) : resolution.height
    }

}

struct SavedPrompt: Identifiable, Codable, Sendable {
    var id = UUID()
    var savedAt = Date()
    var prompt: String
    var negativePrompt: String
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
}

struct CharacterProfile: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var summary: String
    var preserve: String
    var referenceImages: [URL] = []
}
