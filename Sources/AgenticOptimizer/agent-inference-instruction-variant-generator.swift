import AgenticInference
import Foundation
import Primitives

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
    case noCandidates

    public var errorDescription: String? {
        switch self {
        case .duplicateCandidateIdentifier(let identifier):
            return "Instruction candidate identifier '\(identifier.rawValue)' is duplicated."

        case .emptyInstructions(let identifier):
            return "Instruction candidate '\(identifier.rawValue)' has empty instructions."

        case .noCandidates:
            return "Instruction candidate generation requires at least one seed or instruction variant."
        }
    }
}

public struct AgentInferenceInstructionVariantGenerator:
    AgentInferenceRealizationCandidateGenerating,
    Sendable
{
    public let variants: [AgentInferenceInstructionVariant]
    public let includeSeed: Bool
    public let seedIdentifier: AgentInferenceRealizationCandidateIdentifier

    private init(
        parsedVariants variants: [AgentInferenceInstructionVariant],
        includeSeed: Bool,
        seedIdentifier: AgentInferenceRealizationCandidateIdentifier
    ) {
        self.variants = variants
        self.includeSeed = includeSeed
        self.seedIdentifier = seedIdentifier
    }

    public static func parse(
        variants: [AgentInferenceInstructionVariant],
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

        var parsedVariants: [AgentInferenceInstructionVariant] = []

        for variant in variants {
            guard identifiers.insert(variant.identifier).inserted else {
                throw AgentInferenceInstructionVariantGeneratorError
                    .duplicateCandidateIdentifier(
                        variant.identifier
                    )
            }

            let instructions = variant.instructions.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !instructions.isEmpty else {
                throw AgentInferenceInstructionVariantGeneratorError
                    .emptyInstructions(
                        variant.identifier
                    )
            }

            parsedVariants.append(
                AgentInferenceInstructionVariant(
                    identifier: variant.identifier,
                    instructions: instructions,
                    metadata: variant.metadata
                )
            )
        }

        guard includeSeed || !parsedVariants.isEmpty else {
            throw AgentInferenceInstructionVariantGeneratorError.noCandidates
        }

        return Self(
            parsedVariants: parsedVariants,
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
}
