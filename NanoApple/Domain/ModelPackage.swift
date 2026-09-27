import Foundation

struct HubRepository: Codable, Hashable, Sendable {
    let id: String
    let destinationSubdirectory: String
    let includedPaths: [String]?

    init(id: String, destinationSubdirectory: String, includedPaths: [String]? = nil) {
        self.id = id
        self.destinationSubdirectory = destinationSubdirectory
        self.includedPaths = includedPaths
    }
}

struct ModelPackage: Identifiable, Hashable, Sendable {
    enum Requirement: Equatable, Sendable {
        case required
        case optional
    }

    let id: String
    let name: String
    let detail: String
    let approximateBytes: Int64
    let requirement: Requirement
    let repositories: [HubRepository]

    var approximateSize: String {
        ByteCountFormatter.string(fromByteCount: approximateBytes, countStyle: .file)
    }

    func directory(in libraryRoot: URL) -> URL {
        libraryRoot.appending(path: id, directoryHint: .isDirectory)
    }

    static let qwenImage21 = ModelPackage(
        id: "qwen-image-2.1",
        name: "Qwen-Image 2.1",
        detail: String(localized: "model.qwen.detail", defaultValue: "Création, édition, références multiples et transparence"),
        approximateBytes: 33_134_949_212,
        requirement: .required,
        repositories: [
            HubRepository(id: "Qwen/Qwen-Image-2.1", destinationSubdirectory: ".")
        ]
    )

    static let promptEnhancer = ModelPackage(
        id: "qwen-image-2.1-prompt-enhancers",
        name: "Qwen Prompt Enhancers",
        detail: String(localized: "model.enhancer.detail", defaultValue: "Réécriture locale pour la création et la modification d’images"),
        approximateBytes: 37_679_630_252,
        requirement: .optional,
        repositories: [
            HubRepository(id: "Qwen/Qwen-Image-2.1-PE-T2I", destinationSubdirectory: "text-to-image"),
            HubRepository(id: "Qwen/Qwen-Image-2.1-PE-I2I", destinationSubdirectory: "image-to-image")
        ]
    )

    static let qwenImage21GGUFQ6 = ModelPackage(
        id: "qwen-image-2.1-gguf-q6",
        name: "Qwen-Image 2.1 · GGUF Q6",
        detail: String(localized: "model.qwen.gguf_q6.detail", defaultValue: "Modèle quantifié compact avec encodeur Qwen3-VL Q4 et références visuelles"),
        approximateBytes: 12_332_140_664,
        requirement: .optional,
        repositories: [
            HubRepository(
                id: "abenzerps/Qwen-Image-2.1-GGUF",
                destinationSubdirectory: ".",
                includedPaths: [
                    "qwen-image-2.1-Q6_K.gguf",
                    "vae/qwen_image_2.1_vae_bf16.safetensors"
                ]
            ),
            HubRepository(
                id: "Qwen/Qwen3-VL-8B-Instruct-GGUF",
                destinationSubdirectory: "text_encoders",
                includedPaths: [
                    "Qwen3VL-8B-Instruct-Q4_K_M.gguf",
                    "mmproj-Qwen3VL-8B-Instruct-Q8_0.gguf"
                ]
            )
        ]
    )

    static let qwenImage21HereticEncoder = ModelPackage(
        id: "qwen-image-2.1-heretic-encoder",
        name: "Qwen-Image 2.1 · Heretic",
        detail: String(localized: "model.qwen.heretic.detail", defaultValue: "Encodeur de texte alternatif pour le modèle complet · environ 17,5 Go"),
        approximateBytes: 17_500_000_000,
        requirement: .optional,
        repositories: [
            HubRepository(id: "pottokao/Qwen-Image-2.1-Text-Encoder-Heretic", destinationSubdirectory: ".")
        ]
    )

    static let viggleTurbo = ModelPackage(
        id: "qwen-image-2.1-viggle-turbo",
        name: "Viggle Turbo · Qwen-Image 2.1",
        detail: String(localized: "model.viggle.detail", defaultValue: "Adaptateur facultatif pour générer en 6 étapes avec le modèle complet · environ 680 Mo"),
        approximateBytes: 680_000_000,
        requirement: .optional,
        repositories: [
            HubRepository(
                id: "Viggle/Qwen-Image-2.1-viggle-turbo",
                destinationSubdirectory: ".",
                includedPaths: ["Qwen-Image-2.1-viggle-turbo-v0.2.1-6step-lora-r128.safetensors"]
            )
        ]
    )

    static let defaultPackages: [ModelPackage] = [.qwenImage21, .promptEnhancer]
    static let supportedPackages: [ModelPackage] = [
        .qwenImage21, .qwenImage21HereticEncoder, .qwenImage21GGUFQ6, .promptEnhancer, .viggleTurbo
    ]
}

struct ModelInstallationManifest: Codable, Sendable {
    struct RepositorySnapshot: Codable, Sendable {
        struct File: Codable, Sendable {
            let relativePath: String
            let size: Int64
            let sha256: String?
        }

        let repositoryID: String
        let revision: String
        let destinationSubdirectory: String
        let files: [File]
    }

    let formatVersion: Int
    let packageID: String
    let installedAt: Date
    let repositories: [RepositorySnapshot]
}
