// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct ModelAdviceBadge: View {
    let advice: ModelAdvice
    var body: some View {
        Label(advice.rating.title, systemImage: advice.rating.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.13), in: Capsule())
            .help(advice.reason)
            .accessibilityLabel("\(advice.rating.title). \(advice.reason)")
    }
    private var color: Color {
        switch advice.rating {
        case .recommended: .green
        case .conditional: .orange
        case .incompatible: .red
        }
    }
}

struct ModelAdviceView: View {
    let backend: GenerationBackend
    var width = 1024
    var height = 1024

    var body: some View {
        let advice = ModelAdvice.assess(backend, width: width, height: height)
        VStack(alignment: .leading, spacing: 6) {
            ModelAdviceBadge(advice: advice)
            Text(advice.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MacModelGuideView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Choisir pour votre Mac", systemImage: "desktopcomputer")
                .font(.headline)
            Text(MacHardwareProfile.current.summary)
                .font(.callout)
            Text("Officiel complet : précision maximale. Q8 : fidélité élevée et mémoire réduite. AtomicChat Q5 : priorité aux petites configurations, avec des détails moins fidèles.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Les tailles 7,6 et 5,4 Go désignent le générateur. Les paquets complets font environ 17,7 et 11,9 Go avec l’encodeur, la vision et le VAE.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Conseils indicatifs, sans mesure de vitesse sur ce Mac. La mémoire, la puce et le format d’image comptent ; un SSD plus grand ne remplace pas la mémoire. « Sous réserve » invite à commencer petit. « Ne fonctionnera pas » indique une incompatibilité Apple Silicon, Metal ou macOS.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ModelLicenseView: View {
    let package: ModelPackage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Link(package.usesQwenResearchLicense ? "Qwen Research License" : "Apache License 2.0",
                 destination: package.licenseURL)
                .font(.caption.weight(.semibold))
            if package.usesQwenResearchLicense {
                Text(String(localized: "model.license.research", defaultValue: "Recherche ou évaluation uniquement, sans usage commercial. Un usage commercial nécessite une licence distincte de Qwen. Le téléchargement implique l’acceptation de ses conditions."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
