// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

enum GenerationPreset: String, CaseIterable, Codable, Identifiable {
    case none
    case balanced
    case fastDraft
    case highQuality
    case portrait
    case storyboard
    case photorealistic
    case cinematic
    case digitalIllustration
    case anime
    case product
    case socialPortrait

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: String(localized: "preset.none", defaultValue: "Aucun")
        case .balanced: String(localized: "preset.balanced", defaultValue: "Équilibré")
        case .fastDraft: String(localized: "preset.fast", defaultValue: "Brouillon rapide")
        case .highQuality: String(localized: "preset.quality", defaultValue: "Haute qualité")
        case .portrait: String(localized: "preset.portrait", defaultValue: "Portrait")
        case .storyboard: String(localized: "preset.storyboard", defaultValue: "Storyboard")
        case .photorealistic: String(localized: "preset.photorealistic", defaultValue: "Photoréaliste")
        case .cinematic: String(localized: "preset.cinematic", defaultValue: "Cinématique")
        case .digitalIllustration: String(localized: "preset.illustration", defaultValue: "Illustration")
        case .anime: String(localized: "preset.anime", defaultValue: "Anime")
        case .product: String(localized: "preset.product", defaultValue: "Photo produit")
        case .socialPortrait: String(localized: "preset.social", defaultValue: "Réseaux sociaux")
        }
    }

    var detail: String {
        switch self {
        case .none: String(localized: "preset.none.detail", defaultValue: "Aucune consigne de style ajoutée au prompt.")
        case .balanced: String(localized: "preset.balanced.detail", defaultValue: "Bon compromis entre vitesse et détail.")
        case .fastDraft: String(localized: "preset.fast.detail", defaultValue: "Itération rapide avec moins d’étapes.")
        case .highQuality: String(localized: "preset.quality.detail", defaultValue: "Carré 2K et davantage d’étapes.")
        case .portrait: String(localized: "preset.portrait.detail", defaultValue: "Cadrage vertical pour une personne.")
        case .storyboard: String(localized: "preset.storyboard.detail", defaultValue: "Composition horizontale lisible et narrative.")
        case .photorealistic: String(localized: "preset.photorealistic.detail", defaultValue: "Texture naturelle, optique et lumière réalistes.")
        case .cinematic: String(localized: "preset.cinematic.detail", defaultValue: "Cadre ultralarge, lumière de film et profondeur.")
        case .digitalIllustration: String(localized: "preset.illustration.detail", defaultValue: "Illustration numérique riche et nette.")
        case .anime: String(localized: "preset.anime.detail", defaultValue: "Personnage vertical, dessin anime détaillé.")
        case .product: String(localized: "preset.product.detail", defaultValue: "Objet isolé et éclairage de studio commercial.")
        case .socialPortrait: String(localized: "preset.social.detail", defaultValue: "Format 4:5 optimisé pour les publications sociales.")
        }
    }

    var systemImage: String {
        switch self {
        case .none: "circle.slash"
        case .balanced: "slider.horizontal.3"
        case .fastDraft: "hare"
        case .highQuality: "diamond"
        case .portrait: "person.crop.square"
        case .storyboard: "rectangle.split.3x1"
        case .photorealistic: "camera.aperture"
        case .cinematic: "film"
        case .digitalIllustration: "paintbrush.pointed"
        case .anime: "face.smiling"
        case .product: "shippingbox"
        case .socialPortrait: "rectangle.portrait"
        }
    }

    var steps: Int {
        switch self {
        case .fastDraft: 20
        case .none, .balanced, .portrait, .socialPortrait: 30
        case .storyboard, .anime: 28
        case .digitalIllustration, .product: 32
        case .photorealistic, .cinematic: 36
        case .highQuality: 40
        }
    }

    var resolution: CanvasResolution {
        switch self {
        case .portrait: .portrait
        case .storyboard: .landscape
        case .highQuality: .square2K
        case .photorealistic, .product: .square
        case .cinematic: .ultrawide
        case .digitalIllustration: .landscape
        case .anime: .portrait
        case .socialPortrait: .socialPortrait
        default: .square
        }
    }

    func applyingStyle(to prompt: String) -> String {
        guard let suffix = styleSuffix else { return prompt }
        guard !prompt.localizedCaseInsensitiveContains(suffix) else { return prompt }
        return "\(prompt), \(suffix)"
    }

    private var styleSuffix: String? {
        switch self {
        case .photorealistic:
            "photorealistic, natural textures, realistic lighting, high dynamic range, fine photographic detail"
        case .cinematic:
            "cinematic film still, dramatic lighting, deliberate composition, shallow depth of field, subtle film grain"
        case .digitalIllustration:
            "detailed digital illustration, polished composition, precise shapes, rich color palette"
        case .anime:
            "high quality anime illustration, expressive character design, clean line art, detailed background"
        case .product:
            "professional product photography, clean studio background, controlled softbox lighting, crisp commercial detail"
        case .socialPortrait:
            "social media editorial composition, strong focal point, clean negative space, polished color grading"
        default:
            nil
        }
    }
}

enum CanvasResolution: String, CaseIterable, Codable, Identifiable {
    case square
    case landscape
    case portrait
    case socialPortrait
    case ultrawide
    case square2K
    case landscape2K
    case portrait2K
    case custom

    static let minimumDimension = 256
    static let maximumDimension = 2_048
    static let dimensionMultiple = 32

    var id: String { rawValue }

    var title: String {
        switch self {
        case .square: "1024 × 1024 · 1:1"
        case .landscape: "1344 × 768 · 16:9"
        case .portrait: "768 × 1344 · 9:16"
        case .socialPortrait: "1024 × 1280 · 4:5"
        case .ultrawide: "1536 × 672 · 16:7"
        case .square2K: "2048 × 2048 · 1:1"
        case .landscape2K: "2048 × 1152 · 16:9"
        case .portrait2K: "1152 × 2048 · 9:16"
        case .custom: String(localized: "resolution.custom", defaultValue: "Personnalisée…")
        }
    }

    var width: Int {
        switch self {
        case .square: 1_024
        case .landscape: 1_344
        case .portrait: 768
        case .socialPortrait: 1_024
        case .ultrawide: 1_536
        case .square2K: 2_048
        case .landscape2K: 2_048
        case .portrait2K: 1_152
        case .custom: 1_024
        }
    }

    var height: Int {
        switch self {
        case .square: 1_024
        case .landscape: 768
        case .portrait: 1_344
        case .socialPortrait: 1_280
        case .ultrawide: 672
        case .square2K: 2_048
        case .landscape2K: 1_152
        case .portrait2K: 2_048
        case .custom: 1_024
        }
    }

    static func isValidCustomDimension(_ value: Int) -> Bool {
        (minimumDimension...maximumDimension).contains(value) && value.isMultiple(of: dimensionMultiple)
    }
}
