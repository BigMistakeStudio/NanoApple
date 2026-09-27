import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Appearance: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: L10n.Settings.appearanceSystem
            case .light: L10n.Settings.appearanceLight
            case .dark: L10n.Settings.appearanceDark
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    enum Destination: String, CaseIterable, Identifiable {
        case studio
        case characters
        case library
        case prompts
        case models
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .studio: L10n.Navigation.create
            case .characters: L10n.Navigation.characters
            case .library: L10n.Navigation.library
            case .prompts: L10n.Navigation.prompts
            case .models: L10n.Navigation.models
            case .settings: L10n.Navigation.settings
            }
        }

        var systemImage: String {
            switch self {
            case .studio: "sparkles.rectangle.stack"
            case .characters: "person.2.crop.square.stack"
            case .library: "photo.stack"
            case .prompts: "text.book.closed"
            case .models: "externaldrive.badge.icloud"
            case .settings: "gearshape"
            }
        }
    }

    @Published var selection: Destination? = .studio
    @Published var promptToOpenID: UUID?
    @Published var generationBackend: GenerationBackend {
        didSet { UserDefaults.standard.set(generationBackend.rawValue, forKey: generationBackendKey) }
    }
    @Published var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: appearanceKey) }
    }
    @Published private(set) var characters: [CharacterProfile] = []
    @Published private(set) var creations: [CreationRecord] = []
    var didInitializeStudioPrompts = false

    private let charactersKey = "NanoApple.characters.v1"
    private let generationBackendKey = "NanoApple.generationBackend.v1"
    private let appearanceKey = "NanoApple.appearance.v1"

    init() {
        generationBackend = GenerationBackend(
            rawValue: UserDefaults.standard.string(forKey: generationBackendKey) ?? ""
        ) ?? .diffusers
        appearance = Appearance(
            rawValue: UserDefaults.standard.string(forKey: appearanceKey) ?? ""
        ) ?? .dark
        if let data = UserDefaults.standard.data(forKey: charactersKey),
           let decoded = try? JSONDecoder().decode([CharacterProfile].self, from: data) {
            characters = decoded
        }
    }

    func addCharacter(_ character: CharacterProfile) {
        characters.append(character)
        characters.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persistCharacters()
    }

    func deleteCharacters(at offsets: IndexSet) {
        characters.remove(atOffsets: offsets)
        persistCharacters()
    }

    private func persistCharacters() {
        guard let data = try? JSONEncoder().encode(characters) else { return }
        UserDefaults.standard.set(data, forKey: charactersKey)
    }
}
