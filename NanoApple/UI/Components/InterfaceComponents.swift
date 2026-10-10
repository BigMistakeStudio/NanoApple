// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct ContentSafetyCover: View {
    let assessment: ContentSafetyAssessment
    let reveal: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "eye.slash.fill")
                .font(.title2)
            Text(assessment.verdict == .sensitive ? L10n.Safety.sensitive : L10n.Safety.unavailable)
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.center)
            Button(L10n.Safety.reveal, action: reveal)
                .buttonStyle(.bordered)
            Text(L10n.Safety.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SurfaceCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.08))
            }
    }
}

struct SectionHeading: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct StatusBadge: View {
    let title: String
    var color: Color = .secondary

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.13), in: Capsule())
    }
}

struct ModeButton: View {
    let mode: GenerationMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: mode.systemImage)
                    .font(.title2)
                Text(mode.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(isSelected ? Color.accentColor : .secondary.opacity(0.18))
            }
        }
        .buttonStyle(.plain)
    }
}

struct PresetButton: View {
    let preset: GenerationPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(preset.title, systemImage: preset.systemImage)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.04), in: Capsule())
                .overlay { Capsule().stroke(isSelected ? Color.accentColor : .secondary.opacity(0.18)) }
        }
        .buttonStyle(.plain)
    }
}
