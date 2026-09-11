import AgenticInference
import Foundation

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

    public var errorDescription: String? {
        switch self {
        case .duplicateCandidateIdentifier(let identifier):
            return "Demonstration candidate identifier '\(identifier.rawValue)' is duplicated."
        }
    }
}

public struct AgentInferenceDemonstrationVariantGenerator:
    AgentInferenceRealizationCandidateGenerating,
    Sendable
{
    public var variants: [AgentInferenceDemonstrationVariant]
    public var includeSeed: Bool
    public var seedIdentifier: AgentInferenceRealizationCandidateIdentifier

    public init(
        variants: [AgentInferenceDemonstrationVariant],
        includeSeed: Bool = true,
        seedIdentifier: AgentInferenceRealizationCandidateIdentifier = "seed"
    ) {
        self.variants = variants
        self.includeSeed = includeSeed
        self.seedIdentifier = seedIdentifier
    }

    public func generate<Inference: AgentInference>(
        _ inference: Inference.Type,
        examples: [AgentInferenceOptimizationExample<Inference>],
        seed: AgentInferenceRealization
    ) async throws -> [AgentInferenceRealizationCandidate] {
        var identifiers: Set<AgentInferenceRealizationCandidateIdentifier> = []
        var candidates: [AgentInferenceRealizationCandidate] = []

        if includeSeed {
            try insertIdentifier(
                seedIdentifier,
                into: &identifiers
            )

            candidates.append(
                AgentInferenceRealizationCandidate(
                    identifier: seedIdentifier,
                    realization: seed,
                    source: .seed
                )
            )
        }

        for variant in variants {
            try insertIdentifier(
                variant.identifier,
                into: &identifiers
            )

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

    private func insertIdentifier(
        _ identifier: AgentInferenceRealizationCandidateIdentifier,
        into identifiers: inout Set<AgentInferenceRealizationCandidateIdentifier>
    ) throws {
        guard identifiers.insert(identifier).inserted else {
            throw AgentInferenceDemonstrationVariantGeneratorError
                .duplicateCandidateIdentifier(
                    identifier
                )
        }
    }
}
