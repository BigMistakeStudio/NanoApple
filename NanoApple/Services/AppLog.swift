import Foundation

actor AppLog {
    enum Level: String, Sendable {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    static let shared = AppLog()

    private let fileURL: URL
    private let formatter = ISO8601DateFormatter()

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appending(path: "NanoApple/Logs", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "NanoApple.log")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    func append(_ level: Level = .info, category: String, _ message: String) {
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanMessage.isEmpty else { return }
        let entry = "[\(formatter.string(from: Date()))] [\(level.rawValue)] [\(category)] \(cleanMessage)\n"
        guard let data = entry.data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {}
    }

    func contents() -> String {
        guard let data = try? Data(contentsOf: fileURL) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    func url() -> URL { fileURL }
}
