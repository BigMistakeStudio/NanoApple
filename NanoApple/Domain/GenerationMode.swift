// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

enum GenerationMode: String, CaseIterable, Codable, Identifiable {
    case create
    case edit
    case characterSheet
    case transparentAsset
    case viewpointOrbit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .create:
            String(localized: "mode.create", defaultValue: "Créer")
        case .edit:
            String(localized: "mode.edit", defaultValue: "Modifier")
        case .characterSheet:
            String(localized: "mode.character_sheet", defaultValue: "Fiche personnage")
        case .transparentAsset:
            String(localized: "mode.transparent", defaultValue: "PNG transparent")
        case .viewpointOrbit:
            String(localized: "mode.viewpoint_orbit", defaultValue: "Angle de vue")
        }
    }

    var systemImage: String {
        switch self {
        case .create: "sparkles"
        case .edit: "wand.and.stars.inverse"
        case .characterSheet: "person.crop.rectangle.stack"
        case .transparentAsset: "square.on.square.dashed"
        case .viewpointOrbit: "rotate.3d"
        }
    }

    var acceptsReferences: Bool { self != .create }
    var requestsTransparency: Bool { self == .transparentAsset || self == .viewpointOrbit }
}

struct ViewpointOrbitSettings: Codable, Hashable, Sendable {
    enum Rotation: String, CaseIterable, Codable, Identifiable, Sendable {
        case left45, left90, left135, right45, right90, right135, halfTurn, keepAngle

        var id: Self { self }

        var title: String {
            switch self {
            case .left45: String(localized: "orbit.left45", defaultValue: "45° à gauche")
            case .left90: String(localized: "orbit.left90", defaultValue: "90° à gauche")
            case .left135: String(localized: "orbit.left135", defaultValue: "135° à gauche")
            case .right45: String(localized: "orbit.right45", defaultValue: "45° à droite")
            case .right90: String(localized: "orbit.right90", defaultValue: "90° à droite")
            case .right135: String(localized: "orbit.right135", defaultValue: "135° à droite")
            case .halfTurn: String(localized: "orbit.half_turn", defaultValue: "Demi-tour · 180°")
            case .keepAngle: String(localized: "orbit.keep_angle", defaultValue: "Conserver la rotation")
            }
        }

        var instruction: String {
            switch self {
            case .left45: "rotate the camera 45 degrees to the left"
            case .left90: "rotate the camera 90 degrees to the left"
            case .left135: "rotate the camera 135 degrees to the left"
            case .right45: "rotate the camera 45 degrees to the right"
            case .right90: "rotate the camera 90 degrees to the right"
            case .right135: "rotate the camera 135 degrees to the right"
            case .halfTurn: "rotate the camera 180 degrees"
            case .keepAngle: "keep the camera angle"
            }
        }
    }

    enum Elevation: String, CaseIterable, Codable, Identifiable, Sendable {
        case lowAngle, eyeLevel, elevated

        var id: Self { self }

        var title: String {
            switch self {
            case .lowAngle: String(localized: "orbit.low_angle", defaultValue: "Contre-plongée")
            case .eyeLevel: String(localized: "orbit.eye_level", defaultValue: "À hauteur du sujet")
            case .elevated: String(localized: "orbit.elevated", defaultValue: "Vue en plongée")
            }
        }

        var instruction: String {
            switch self {
            case .lowAngle: "low angle"
            case .eyeLevel: "eye level"
            case .elevated: "elevated"
            }
        }
    }

    var rotation: Rotation = .right45
    var elevation: Elevation = .eyeLevel

    var isValid: Bool { rotation != .keepAngle || elevation != .eyeLevel }

    var prompt: String {
        "<orbit> \(rotation.instruction), \(elevation.instruction). The image has alpha channel and the background is transparent."
    }
}
