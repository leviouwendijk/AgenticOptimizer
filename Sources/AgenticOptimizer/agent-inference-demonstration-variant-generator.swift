import AgenticInference
import Foundation
import Primitives

public struct AgentInferenceDemonstrationVariant:
    Sendable,
    Codable,
    Hashable
{
    public var identifier: AgentInferenceRealizationCandidateIdentifier
    public var demonstrations: [AgentInferenceDemonstration]
    public var metadata: [String: String]

    public init(
        identifier: AgentInferenceRealizationCandidateIdentifier,
        demonstrations: [AgentInferenceDemonstration],
        metadata: [String: String] = [:]
    ) {
        self.identifier = identifier
        self.demonstrations = demonstrations
        self.metadata = metadata
    }
}

public enum AgentInferenceDemonstrationVariantGeneratorError:
    Error,
    Sendable,
    LocalizedError
{
    case duplicateCandidateIdentifier(
        AgentInferenceRealizationCandidateIdentifier
    )
    case noCandidates

    public var errorDescription: String? {
        switch self {
        case .duplicateCandidateIdentifier(let identifier):
            return "Demonstration candidate identifier '\(identifier.rawValue)' is duplicated."

        case .noCandidates:
            return "Demonstration candidate generation requires at least one seed or demonstration variant."
        }
    }
}

public struct AgentInferenceDemonstrationVariantGenerator:
    AgentInferenceRealizationCandidateGenerating,
    Sendable
{
    public let variants: [AgentInferenceDemonstrationVariant]
    public let includeSeed: Bool
    public let seedIdentifier: AgentInferenceRealizationCandidateIdentifier

    private init(
        parsedVariants variants: [AgentInferenceDemonstrationVariant],
        includeSeed: Bool,
        seedIdentifier: AgentInferenceRealizationCandidateIdentifier
    ) {
        self.variants = variants
        self.includeSeed = includeSeed
        self.seedIdentifier = seedIdentifier
    }

    public static func parse(
        variants: [AgentInferenceDemonstrationVariant],
        includeSeed: Bool = true,
        seedIdentifier: AgentInferenceRealizationCandidateIdentifier = "seed"
    ) throws -> Self {
        var identifiers: Set<
            AgentInferenceRealizationCandidateIdentifier
        > = []

        if includeSeed {
            identifiers.insert(
                seedIdentifier
            )
        }

        for variant in variants {
            guard identifiers.insert(variant.identifier).inserted else {
                throw AgentInferenceDemonstrationVariantGeneratorError
                    .duplicateCandidateIdentifier(
                        variant.identifier
                    )
            }
        }

        guard includeSeed || !variants.isEmpty else {
            throw AgentInferenceDemonstrationVariantGeneratorError.noCandidates
        }

        return Self(
            parsedVariants: variants,
            includeSeed: includeSeed,
            seedIdentifier: seedIdentifier
        )
    }

    public func generate<Inference: AgentInference>(
        _ inference: Inference.Type,
        examples: [AgentInferenceOptimizationExample<Inference>],
        seed: AgentInferenceRealization
    ) async throws -> [AgentInferenceRealizationCandidate] {
        var candidates: [AgentInferenceRealizationCandidate] = []

        if includeSeed {
            candidates.append(
                AgentInferenceRealizationCandidate(
                    identifier: seedIdentifier,
                    realization: seed,
                    source: .seed
                )
            )
        }

        for variant in variants {
            var realization = seed
            realization.demonstrations = variant.demonstrations

            candidates.append(
                AgentInferenceRealizationCandidate(
                    identifier: variant.identifier,
                    realization: realization,
                    source: .demonstration_variant,
                    metadata: variant.metadata
                )
            )
        }

        return candidates
    }
}
