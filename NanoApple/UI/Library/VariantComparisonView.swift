// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

struct VariantComparisonItem {
    let project: ImageProject
    let variant: ProjectVariant
    let imageURL: URL
}

struct VariantComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var revealedSafetyVariantIDs: Set<UUID> = []

    let items: [VariantComparisonItem]
    let canRegenerate: Bool
    let onOpen: (VariantComparisonItem) -> Void
    let onRegenerate: (VariantComparisonItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.Library.comparisonTitle)
                        .font(.title2.bold())
                    Text(L10n.Library.comparisonSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.Common.cancel, systemImage: "xmark") { dismiss() }
            }

            ScrollView {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(0..<min(items.count, 2), id: \.self) { index in
                        comparisonColumn(items[index], label: index == 0 ? "A" : "B")
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .padding(24)
        .frame(minWidth: 980, minHeight: 700)
    }

    private func comparisonColumn(_ item: VariantComparisonItem, label: String) -> some View {
        let request = item.variant.request
        return SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(L10n.Library.comparisonVariant) \(label)")
                            .font(.headline)
                        Text(item.project.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.variant.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if item.variant.evaluation?.verdict == .accepted {
                        Label(L10n.Library.comparisonAccepted, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                if let image = NSImage(contentsOf: item.imageURL) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            if appModel.nsfwFilterEnabled,
                               let assessment = item.variant.contentSafety,
                               assessment.needsCover,
                               !revealedSafetyVariantIDs.contains(item.variant.id) {
                                ContentSafetyCover(assessment: assessment) {
                                    revealedSafetyVariantIDs.insert(item.variant.id)
                                }
                            }
                        }
                } else {
                    ContentUnavailableView(L10n.Library.comparisonImageMissing, systemImage: "photo.badge.exclamationmark")
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }

                HStack {
                    Button(L10n.Library.resumeVariant, systemImage: "arrow.right.circle") {
                        onOpen(item)
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button(L10n.Library.regenerateVariant, systemImage: "arrow.clockwise") {
                        onRegenerate(item)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRegenerate)
                }

                Divider()
                Text(L10n.Library.comparisonSettings)
                    .font(.headline)
                setting(L10n.Studio.engine,
                        request.backend?.name ?? L10n.Library.comparisonUnknownEngine)
                setting(L10n.Studio.mode, request.mode.title)
                setting(L10n.Studio.preset, request.preset.title)
                setting(L10n.Library.comparisonRequestedSize, "\(request.width) × \(request.height) px")
                if let width = item.variant.sourcePixelWidth,
                   let height = item.variant.sourcePixelHeight {
                    setting(L10n.Library.comparisonActualSize, "\(width) × \(height) px")
                }
                setting(L10n.Studio.steps, String(request.steps))
                setting(L10n.Studio.seed,
                        request.randomizeSeed ? L10n.Studio.randomSeed : String(request.seed))
                setting(L10n.Studio.enhancePrompt,
                        request.enhancePrompt ? L10n.Library.comparisonYes : L10n.Library.comparisonNo)
                setting(L10n.Studio.viggleTurbo,
                        request.useViggleTurbo == true ? L10n.Library.comparisonYes : L10n.Library.comparisonNo)
                setting(L10n.Studio.consistencyLoRA,
                        request.useConsistencyLoRA == true ? L10n.Library.comparisonYes : L10n.Library.comparisonNo)
                setting(L10n.Studio.references, String(request.referenceImages.count))

                Divider()
                promptSection(L10n.Studio.originalPrompt, text: request.originalPrompt ?? request.prompt)
                if let enhanced = request.enhancedPrompt,
                   !enhanced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    promptSection(L10n.Studio.enhancedPrompt, text: enhanced)
                } else if request.originalPrompt != nil && request.prompt != request.originalPrompt {
                    promptSection(L10n.Studio.finalPrompt, text: request.prompt)
                }
                if !request.negativePrompt.isEmpty {
                    promptSection(L10n.Studio.negativePrompt, text: request.negativePrompt)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func setting(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
    }

    private func promptSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.callout.weight(.semibold))
            ScrollView {
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(10)
            .frame(height: 140)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
