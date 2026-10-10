// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

@main
struct ModelLicenseChecks {
    static func main() throws {
        let resources = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for package in ModelPackage.supportedPackages {
            let destination = package.directory(in: root)
            try package.writeLicenseDocuments(to: destination, resources: resources)
            let legal = destination.appending(path: "Legal")
            let apache = legal.appending(path: "Apache-2.0.txt")
            let copied = try Data(contentsOf: apache)
            let original = try Data(contentsOf: resources.appending(path: "Apache-2.0.txt"))
            precondition(copied == original)
            let research = legal.appending(path: "Qwen-Research-LICENSE.txt")
            precondition(FileManager.default.fileExists(atPath: research.path) == package.usesQwenResearchLicense)
            let notice = try String(contentsOf: destination.appending(path: "NanoApple-MODEL-NOTICES.txt"), encoding: .utf8)
            for repo in package.repositories { precondition(notice.contains(repo.id)) }
        }
        do {
            try ModelPackage.qwenImage21Turbo.writeLicenseDocuments(to: root.appending(path: "missing"), resources: root.appending(path: "absent"))
            preconditionFailure("Missing licenses must prevent installation")
        } catch {}
        print("Model license installation checks passed for all packages")
    }
}
