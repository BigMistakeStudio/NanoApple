import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LogsViewModel: ObservableObject {
    @Published var text = ""
    @Published var lastError: String?

    func refresh() {
        Task {
            text = await AppLog.shared.contents()
        }
    }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func export() {
        let panel = NSSavePanel()
        panel.title = L10n.Logs.export
        panel.nameFieldStringValue = "NanoApple-Logs.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try text.write(to: destination, atomically: true, encoding: .utf8)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

struct LogsView: View {
    @StateObject private var model = LogsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.Logs.title).font(.title2.bold())
                    Text(L10n.Logs.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.Logs.refresh, systemImage: "arrow.clockwise") { model.refresh() }
                Button(L10n.Logs.copy, systemImage: "doc.on.doc") { model.copy() }
                Button(L10n.Logs.export, systemImage: "square.and.arrow.up") { model.export() }
                    .buttonStyle(.borderedProminent)
            }

            ScrollView([.horizontal, .vertical]) {
                Text(model.text.isEmpty ? L10n.Logs.empty : model.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(18)
        .frame(minWidth: 760, minHeight: 480)
        .onAppear { model.refresh() }
    }
}

struct ToolsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu(L10n.Logs.toolsMenu) {
            Button(L10n.Logs.menuItem) { openWindow(id: "logs") }
                .keyboardShortcut("l", modifiers: [.command, .option])
        }
    }
}
