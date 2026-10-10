// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum ImageExportService {
    static func saveCopy(of source: URL) throws {
        let panel = NSSavePanel()
        panel.title = L10n.Library.saveAs
        panel.nameFieldStringValue = source.lastPathComponent
        if let type = UTType(filenameExtension: source.pathExtension) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try Data(contentsOf: source).write(to: destination, options: .atomic)
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
