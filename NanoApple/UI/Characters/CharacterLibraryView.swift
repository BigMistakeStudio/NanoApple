import SwiftUI

struct CharacterLibraryView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isPresentingEditor = false

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.Characters.title).font(.largeTitle.bold())
                        Text(L10n.Characters.subtitle).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.Characters.new, systemImage: "plus") { isPresentingEditor = true }
                        .buttonStyle(.borderedProminent)
                }

                if appModel.characters.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.Characters.emptyTitle, systemImage: "person.crop.rectangle.stack")
                    } description: {
                        Text(L10n.Characters.emptyDescription)
                    } actions: {
                        Button(L10n.Characters.create) { isPresentingEditor = true }
                    }
                    .frame(maxWidth: .infinity, minHeight: 440)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(appModel.characters) { character in
                            SurfaceCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(character.name).font(.headline)
                                    Text(character.summary).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                                    Label("\(character.referenceImages.count) \(L10n.Characters.references)", systemImage: "photo.stack")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .sheet(isPresented: $isPresentingEditor) {
            CharacterEditor { profile in
                appModel.addCharacter(profile)
                isPresentingEditor = false
            } onCancel: {
                isPresentingEditor = false
            }
        }
    }
}

private struct CharacterEditor: View {
    @State private var name = ""
    @State private var summary = ""
    @State private var preserve = ""

    let onSave: (CharacterProfile) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.Characters.new)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
            Divider()
            Form {
                TextField(L10n.Characters.name, text: $name)
                TextField(L10n.Characters.description, text: $summary, axis: .vertical)
                TextField(L10n.Characters.preserve, text: $preserve, axis: .vertical)
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button(L10n.Characters.cancel, action: onCancel)
                Button(L10n.Characters.save) {
                    onSave(CharacterProfile(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        summary: summary,
                        preserve: preserve
                    ))
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(18)
        }
        .frame(width: 620, height: 440)
    }
}
