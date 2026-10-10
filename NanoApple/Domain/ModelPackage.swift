// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

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

    /// Research-only terms apply to the image weights and their derivatives.
    /// Separate Apache-2.0 components do not override those terms.
    var usesQwenResearchLicense: Bool {
        id != Self.nsfwClassifier.id && id != Self.qwenImage21HereticEncoder.id
    }

    var licenseURL: URL {
        let repository = usesQwenResearchLicense
            ? "Qwen/Qwen-Image-2.1-Turbo" : repositories[0].id
        let path = usesQwenResearchLicense ? "blob/main/LICENSE" : ""
        return URL(string: "https://huggingface.co/\(repository)/\(path)")!
    }

    /// Keep the agreements with installed weights, including partial installations.
    /// Missing bundled legal resources stop installation before any weights are written.
    func writeLicenseDocuments(to directory: URL, resources: URL) throws {
        let names = usesQwenResearchLicense
            ? ["Qwen-Research-LICENSE.txt", "Apache-2.0.txt", "NOTICE.txt"]
            : ["Apache-2.0.txt", "NOTICE.txt"]
        let destination = directory.appending(path: "Legal", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in names {
            let data = try Data(contentsOf: resources.appending(path: name))
            try data.write(to: destination.appending(path: name), options: .atomic)
        }
        let sources = repositories.map { "- https://huggingface.co/\($0.id)" }.joined(separator: "\n")
        let terms = usesQwenResearchLicense
            ? "Qwen image weights: research or evaluation only, non-commercial. Commercial use requires a separate license from Qwen. Apache-2.0 components retain their separate terms."
            : "This package is distributed under Apache-2.0. See the original repository for attribution and notices."
        let notice = """
        NanoApple model package: \(id)
        \(terms)
        Sources (repository revisions and file hashes are recorded in manifest.json):
        \(sources)
        License copies: Legal/
        NanoApple downloads original files without modifying the model weights.
        """
        try Data(notice.utf8).write(to: directory.appending(path: "NanoApple-MODEL-NOTICES.txt"), options: .atomic)
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

    static let qwenImage21Turbo = ModelPackage(
        id: "qwen-image-2.1-turbo",
        name: String(localized: "model.turbo.full.name", defaultValue: "Turbo · Officiel complet · 32,5 Go"),
        detail: String(localized: "model.qwen.turbo.detail", defaultValue: "Modèle officiel accéléré pour la création, les retouches et la transparence · 8 étapes"),
        approximateBytes: 32_451_624_677,
        requirement: .optional,
        repositories: [
            HubRepository(id: "Qwen/Qwen-Image-2.1-Turbo", destinationSubdirectory: ".")
        ]
    )

    static let qwenImage21TurboQ8 = turboGGUFPackage(
        id: "qwen-image-2.1-turbo-gguf-q8", name: String(localized: "model.turbo.q8.name", defaultValue: "Turbo · GGUF Q8 · générateur 7,6 Go"),
        detail: String(localized: "model.turbo.q8.detail", defaultValue: "Fidélité élevée · 8 étapes · encodeur Q8, vision et VAE inclus dans la taille totale"),
        variant: .q8, approximateBytes: 17_728_873_656
    )

    static let qwenImage21TurboAtomicQ5 = turboGGUFPackage(
        id: "qwen-image-2.1-turbo-atomic-q5", name: String(localized: "model.turbo.atomic.name", defaultValue: "Turbo · AtomicChat Q5 · générateur 5,4 Go"),
        detail: String(localized: "model.turbo.atomic.detail", defaultValue: "Pour les petites configurations · 8 étapes · encodeur Q4, vision et VAE inclus · détails moins fidèles"),
        variant: .atomicQ5, approximateBytes: 11_854_752_952
    )

    private static func turboGGUFPackage(id: String, name: String, detail: String,
                                        variant: QwenTurboGGUFVariant, approximateBytes: Int64) -> ModelPackage {
        ModelPackage(id: id, name: name, detail: detail, approximateBytes: approximateBytes,
                     requirement: .optional, repositories: [
            HubRepository(id: "AtomicChat/Qwen-Image-2.1-Turbo-GGUF", destinationSubdirectory: ".",
                          includedPaths: [variant.diffusionFile, "README.md"]),
            HubRepository(id: "Qwen/Qwen3-VL-8B-Instruct-GGUF", destinationSubdirectory: "text_encoders",
                          includedPaths: [URL(fileURLWithPath: variant.textEncoderFile).lastPathComponent,
                                          URL(fileURLWithPath: variant.visionEncoderFile).lastPathComponent]),
            HubRepository(id: "Comfy-Org/Qwen-Image-2.1", destinationSubdirectory: ".",
                          includedPaths: [variant.vaeFile])
        ])
    }

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
                includedPaths: ["Qwen-Image-2.1-viggle-turbo-v0.2.1-6step-lora-r128.safetensors", "LICENSE", "NOTICE", "README.md"]
            )
        ]
    )

    static let consistencyLoRA = ModelPackage(
        id: "qwen-image-2.1-consistency-lora",
        name: "Consistency LoRA · Qwen-Image 2.1",
        detail: String(localized: "model.consistency.detail", defaultValue: "Adaptateur facultatif pour préserver le cadrage lors des retouches avec une image de référence · environ 159 Mo"),
        approximateBytes: 159_436_496,
        requirement: .optional,
        repositories: [
            HubRepository(
                id: "ausboss/Qwen-Image-2.1-Consistency-LoRA",
                destinationSubdirectory: ".",
                includedPaths: ["qwen-image-2.1-consistency.safetensors", "README.md"]
            )
        ]
    )

    static let nsfwClassifier = ModelPackage(
        id: "nsfw-image-classifier",
        name: String(localized: "model.nsfw.name", defaultValue: "Filtre NSFW"),
        detail: String(localized: "model.nsfw.detail", defaultValue: "Analyse locale des nouvelles images avant leur affichage · environ 343 Mo"),
        approximateBytes: 343_000_000,
        requirement: .optional,
        repositories: [
            HubRepository(
                id: "Falconsai/nsfw_image_detection",
                destinationSubdirectory: ".",
                includedPaths: ["config.json", "preprocessor_config.json", "model.safetensors", "README.md"]
            )
        ]
    )

    static let viewpointOrbitWeightPath = "checkpoints/steps2000res768/orbit_alpha_lora_gate_up_split.safetensors"

    static let viewpointOrbit = ModelPackage(
        id: "qwen-image-2.1-viewpoint-orbit",
        name: "Viewpoint Orbit · Qwen-Image 2.1",
        detail: String(localized: "model.orbit.detail", defaultValue: "Changer l’angle d’un sujet transparent avec le modèle complet · environ 168 Mo · licence Qwen Research"),
        approximateBytes: 167_833_192,
        requirement: .optional,
        repositories: [
            HubRepository(
                id: "ML-Intern-lab/Qwen-Image-2.1-viewpoint-orbit-LoRA",
                destinationSubdirectory: ".",
                includedPaths: [viewpointOrbitWeightPath, "LICENSE", "README.md"]
            )
        ]
    )

    static let defaultPackages: [ModelPackage] = [.qwenImage21, .promptEnhancer]
    static let supportedPackages: [ModelPackage] = [
        .qwenImage21Turbo, .qwenImage21TurboQ8, .qwenImage21TurboAtomicQ5,
        .qwenImage21, .qwenImage21HereticEncoder,
        .promptEnhancer, .viggleTurbo, .consistencyLoRA, .viewpointOrbit, .nsfwClassifier
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
