import Agentic
import AgenticInference
import Foundation
import Primitives

public struct InferenceDemonstrationVariant:
    Sendable,
    Codable,
    Hashable
{
    public var identifier: InferenceRealizationCandidateIdentifier
    public var demonstrations: [InferenceDemonstration]
    public var metadata: [String: String]

    public init(
        identifier: InferenceRealizationCandidateIdentifier,
        demonstrations: [InferenceDemonstration],
        metadata: [String: String] = [:]
    ) {
        self.identifier = identifier
        self.demonstrations = demonstrations
        self.metadata = metadata
    }
}

public enum InferenceDemonstrationVariantGeneratorError:
    Error,
    Sendable,
    LocalizedError
{
    case duplicateCandidateIdentifier(
        InferenceRealizationCandidateIdentifier
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

public struct InferenceDemonstrationVariantGenerator:
    InferenceRealizationCandidateGenerating,
    Sendable
{
    public let variants: [InferenceDemonstrationVariant]
    public let includeSeed: Bool
    public let seedIdentifier: InferenceRealizationCandidateIdentifier

    private init(
        parsedVariants variants: [InferenceDemonstrationVariant],
        includeSeed: Bool,
        seedIdentifier: InferenceRealizationCandidateIdentifier
    ) {
        self.variants = variants
        self.includeSeed = includeSeed
        self.seedIdentifier = seedIdentifier
    }

    public static func parse(
        variants: [InferenceDemonstrationVariant],
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

        for variant in variants {
            guard identifiers.insert(variant.identifier).inserted else {
                throw InferenceDemonstrationVariantGeneratorError
                    .duplicateCandidateIdentifier(
                        variant.identifier
                    )
            }
        }

        guard includeSeed || !variants.isEmpty else {
            throw InferenceDemonstrationVariantGeneratorError.noCandidates
        }

        return Self(
            parsedVariants: variants,
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
            realization.demonstrations = variant.demonstrations

            candidates.append(
                InferenceRealizationCandidate(
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