import Foundation

enum GenerationMode: String, CaseIterable, Codable, Identifiable {
    case create
    case edit
    case characterSheet
    case transparentAsset

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
        }
    }

    var systemImage: String {
        switch self {
        case .create: "sparkles"
        case .edit: "wand.and.stars.inverse"
        case .characterSheet: "person.crop.rectangle.stack"
        case .transparentAsset: "square.on.square.dashed"
        }
    }

    var acceptsReferences: Bool { self != .create }
    var requestsTransparency: Bool { self == .transparentAsset }
}
