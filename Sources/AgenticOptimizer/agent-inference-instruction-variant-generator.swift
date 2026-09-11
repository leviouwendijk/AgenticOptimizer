import AgenticInference
import Foundation

public struct AgentInferenceInstructionVariant:
    Sendable,
    Codable,
    Hashable
{
    public var identifier: AgentInferenceRealizationCandidateIdentifier
    public var instructions: String
    public var metadata: [String: String]

    public init(
        identifier: AgentInferenceRealizationCandidateIdentifier,
        instructions: String,
        metadata: [String: String] = [:]
    ) {
        self.identifier = identifier
        self.instructions = instructions
        self.metadata = metadata
    }
}

public enum AgentInferenceInstructionVariantGeneratorError:
    Error,
    Sendable,
    LocalizedError
{
    case duplicateCandidateIdentifier(
        AgentInferenceRealizationCandidateIdentifier
    )
    case emptyInstructions(
        AgentInferenceRealizationCandidateIdentifier
    )

    public var errorDescription: String? {
        switch self {
        case .duplicateCandidateIdentifier(let identifier):
            return "Instruction candidate identifier '\(identifier.rawValue)' is duplicated."

        case .emptyInstructions(let identifier):
            return "Instruction candidate '\(identifier.rawValue)' has empty instructions."
        }
    }
}

public struct AgentInferenceInstructionVariantGenerator:
    AgentInferenceRealizationCandidateGenerating,
    Sendable
{
    public var variants: [AgentInferenceInstructionVariant]
    public var includeSeed: Bool
    public var seedIdentifier: AgentInferenceRealizationCandidateIdentifier

    public init(
        variants: [AgentInferenceInstructionVariant],
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

            guard
                !variant.instructions
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty
            else {
                throw AgentInferenceInstructionVariantGeneratorError
                    .emptyInstructions(
                        variant.identifier
                    )
            }

            var realization = seed
            realization.instructions = variant.instructions

            candidates.append(
                AgentInferenceRealizationCandidate(
                    identifier: variant.identifier,
                    realization: realization,
                    source: .instruction_variant,
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
            throw AgentInferenceInstructionVariantGeneratorError
                .duplicateCandidateIdentifier(
                    identifier
                )
        }
    }
}
