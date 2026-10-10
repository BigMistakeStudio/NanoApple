// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

@MainActor
final class ModelInstaller: ObservableObject {
    enum State: Equatable {
        case idle
        case preparing
        case downloading(progress: Double, currentFile: String, receivedBytes: Int64, totalBytes: Int64)
        case verifying(progress: Double, currentFile: String)
        case installed
        case paused
        case failed(String)

        var isActive: Bool {
            switch self {
            case .preparing, .downloading, .verifying: true
            default: false
            }
        }
    }

    @Published private(set) var states: [String: State] = [:]
    @Published private(set) var activePackageID: String?

    private let hub = HuggingFaceHubClient()
    private var installationTask: Task<Void, Never>?

    init() {
        for package in ModelPackage.supportedPackages {
            states[package.id] = .idle
        }
    }

    var isBusy: Bool { installationTask != nil }

    func state(for package: ModelPackage) -> State {
        states[package.id] ?? .idle
    }

    func install(
        _ packages: [ModelPackage],
        in libraryRoot: URL,
        modelLibrary: ModelLibrary
    ) {
        guard installationTask == nil else { return }
        installationTask = Task { [weak self] in
            guard let self else { return }
            do {
                for package in packages {
                    try Task.checkCancellation()
                    activePackageID = package.id
                    states[package.id] = .preparing
                    await AppLog.shared.append(category: "Models", "Installation de \(package.name) dans \(libraryRoot.path).")
                    _ = try await hub.install(package, in: libraryRoot) { [weak self] update in
                        await self?.apply(update, to: package.id)
                    }
                    states[package.id] = .installed
                    modelLibrary.refresh(in: libraryRoot)
                    await AppLog.shared.append(category: "Models", "\(package.name) est installé et vérifié.")
                }
            } catch is CancellationError {
                if let activePackageID {
                    states[activePackageID] = .paused
                    await AppLog.shared.append(.warning, category: "Models", "Installation de \(activePackageID) interrompue.")
                }
            } catch {
                if let activePackageID {
                    states[activePackageID] = .failed(error.localizedDescription)
                    await AppLog.shared.append(.error, category: "Models", "\(activePackageID) : \(error.localizedDescription)")
                }
            }
            activePackageID = nil
            installationTask = nil
        }
    }

    func cancel() {
        installationTask?.cancel()
    }

    private func apply(_ update: HubInstallProgress, to packageID: String) {
        let total = max(update.totalBytes, 1)
        let fraction = min(max(Double(update.receivedBytes) / Double(total), 0), 1)
        switch update.phase {
        case .preparing:
            states[packageID] = .preparing
        case .downloading:
            states[packageID] = .downloading(
                progress: fraction,
                currentFile: update.currentFile,
                receivedBytes: update.receivedBytes,
                totalBytes: update.totalBytes
            )
        case .verifying:
            states[packageID] = .verifying(progress: fraction, currentFile: update.currentFile)
        }
    }
}
