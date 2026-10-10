// SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

struct ContentSafetyAssessment: Codable, Equatable, Sendable {
    enum Verdict: String, Codable, Sendable { case clear, sensitive, unavailable }

    static let threshold = 0.50
    let verdict: Verdict
    let nsfwProbability: Double?

    init(nsfwProbability: Double) {
        self.nsfwProbability = nsfwProbability
        verdict = nsfwProbability >= Self.threshold ? .sensitive : .clear
    }

    static let unavailable = ContentSafetyAssessment(verdict: .unavailable, nsfwProbability: nil)

    private init(verdict: Verdict, nsfwProbability: Double?) {
        self.verdict = verdict
        self.nsfwProbability = nsfwProbability
    }

    var needsCover: Bool { verdict != .clear }
}

struct ImageProject: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var variants: [ProjectVariant]
    var draft: GenerationRequest?

    init(name: String) {
        id = UUID()
        self.name = name
        createdAt = Date()
        updatedAt = createdAt
        variants = []
        draft = nil
    }
}

struct ProjectVariant: Identifiable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case generation
        case variation
        case upscale2x
        case upscale4x

        var title: String {
            switch self {
            case .generation:
                String(localized: "project.variant.generation", defaultValue: "Génération")
            case .variation:
                String(localized: "project.variant.variation", defaultValue: "Variante")
            case .upscale2x:
                String(localized: "project.variant.upscale2x", defaultValue: "Agrandissement 2×")
            case .upscale4x:
                String(localized: "project.variant.upscale4x", defaultValue: "Agrandissement 4×")
            }
        }
    }

    var id: UUID
    var createdAt: Date
    var kind: Kind
    var parentID: UUID?
    var relativeImagePath: String
    var request: GenerationRequest
    var sourcePixelWidth: Int?
    var sourcePixelHeight: Int?
    var evaluation: ImageEvaluation?
    var contentSafety: ContentSafetyAssessment?

    init(
        kind: Kind,
        parentID: UUID?,
        relativeImagePath: String,
        request: GenerationRequest,
        sourcePixelWidth: Int? = nil,
        sourcePixelHeight: Int? = nil,
        contentSafety: ContentSafetyAssessment? = nil
    ) {
        id = UUID()
        createdAt = Date()
        self.kind = kind
        self.parentID = parentID
        self.relativeImagePath = relativeImagePath
        self.request = request
        self.sourcePixelWidth = sourcePixelWidth
        self.sourcePixelHeight = sourcePixelHeight
        self.contentSafety = contentSafety
        evaluation = nil
    }
}

struct ImageEvaluation: Codable, Sendable {
    enum Verdict: String, CaseIterable, Codable, Identifiable, Sendable {
        case toReview
        case accepted
        case toCorrect

        var id: String { rawValue }

        var title: String {
            switch self {
            case .toReview: String(localized: "evaluation.verdict.review", defaultValue: "À examiner")
            case .accepted: String(localized: "evaluation.verdict.accepted", defaultValue: "Conforme")
            case .toCorrect: String(localized: "evaluation.verdict.correct", defaultValue: "À corriger")
            }
        }
    }

    enum Issue: String, CaseIterable, Codable, Identifiable, Sendable {
        case text
        case anatomy
        case identity
        case composition
        case preservation
        case transparency
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .text: String(localized: "evaluation.issue.text", defaultValue: "Texte dans l’image")
            case .anatomy: String(localized: "evaluation.issue.anatomy", defaultValue: "Action ou anatomie")
            case .identity: String(localized: "evaluation.issue.identity", defaultValue: "Identité du sujet")
            case .composition: String(localized: "evaluation.issue.composition", defaultValue: "Cadrage ou composition")
            case .preservation: String(localized: "evaluation.issue.preservation", defaultValue: "Éléments à préserver")
            case .transparency: String(localized: "evaluation.issue.transparency", defaultValue: "Transparence ou contours")
            case .other: String(localized: "evaluation.issue.other", defaultValue: "Autre défaut")
            }
        }
    }

    var verdict: Verdict = .toReview
    var issues: [Issue] = []
    var note: String = ""
    var preferenceNote: String = ""
    var reviewedAt: Date?
}
