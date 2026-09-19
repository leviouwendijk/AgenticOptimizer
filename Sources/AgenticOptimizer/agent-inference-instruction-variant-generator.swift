import Agentic
import AgenticInference
import Foundation
import Primitives

public struct InferenceInstructionVariant:
    Sendable,
    Codable,
    Hashable
{
    public var identifier: InferenceRealizationCandidateIdentifier
    public var instructions: String
    public var metadata: [String: String]

    public init(
        identifier: InferenceRealizationCandidateIdentifier,
        instructions: String,
        metadata: [String: String] = [:]
    ) {
        self.identifier = identifier
        self.instructions = instructions
        self.metadata = metadata
    }
}

public enum InferenceInstructionVariantGeneratorError:
    Error,
    Sendable,
    LocalizedError
{
    case duplicateCandidateIdentifier(
        InferenceRealizationCandidateIdentifier
    )
    case emptyInstructions(
        InferenceRealizationCandidateIdentifier
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

public struct InferenceInstructionVariantGenerator:
    InferenceRealizationCandidateGenerating,
    Sendable
{
    public let variants: [InferenceInstructionVariant]
    public let includeSeed: Bool
    public let seedIdentifier: InferenceRealizationCandidateIdentifier

    private init(
        parsedVariants variants: [InferenceInstructionVariant],
        includeSeed: Bool,
        seedIdentifier: InferenceRealizationCandidateIdentifier
    ) {
        self.variants = variants
        self.includeSeed = includeSeed
        self.seedIdentifier = seedIdentifier
    }

    public static func parse(
        variants: [InferenceInstructionVariant],
        includeSeed: Bool = true,
        seedIdentifier: InferenceRealizationCandidateIdentifier = "seed"
    ) throws -> Self {
        var identifiers: Set<
            InferenceRealizationCandidateIdentifier
        > = []

        if includeSeed {
            identifiers.insert(
                seedIdentifier
            )
        }

        var parsedVariants: [InferenceInstructionVariant] = []

        for variant in variants {
            guard identifiers.insert(variant.identifier).inserted else {
                throw InferenceInstructionVariantGeneratorError
                    .duplicateCandidateIdentifier(
                        variant.identifier
                    )
            }

            let instructions = variant.instructions.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !instructions.isEmpty else {
                throw InferenceInstructionVariantGeneratorError
                    .emptyInstructions(
                        variant.identifier
                    )
            }

            parsedVariants.append(
                InferenceInstructionVariant(
                    identifier: variant.identifier,
                    instructions: instructions,
                    metadata: variant.metadata
                )
            )
        }

        guard includeSeed || !parsedVariants.isEmpty else {
            throw InferenceInstructionVariantGeneratorError.noCandidates
        }

        return Self(
            parsedVariants: parsedVariants,
            includeSeed: includeSeed,
            seedIdentifier: seedIdentifier
        )
    }

    public func generate<InferenceType: Inference>(
        _ inference: InferenceType.Type,
        examples: [InferenceOptimizationExample<InferenceType>],
        seed: InferenceRealizationConfiguration
    ) async throws -> [InferenceRealizationCandidate] {
        var candidates: [InferenceRealizationCandidate] = []

        if includeSeed {
            candidates.append(
                InferenceRealizationCandidate(
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
                InferenceRealizationCandidate(
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