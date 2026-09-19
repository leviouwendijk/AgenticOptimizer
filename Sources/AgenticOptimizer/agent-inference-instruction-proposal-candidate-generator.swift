import Agentic
import AgenticInference
import Foundation
import Primitives

public enum InferenceInstructionProposalGeneratorError:
    Error,
    Sendable,
    LocalizedError
{
    case invalidMaximumProposals(Int)
    case emptyProposedInstructions(Int)
    case duplicateCandidateIdentifier(
        InferenceRealizationCandidateIdentifier
    )
    case noCandidatesProduced

    public var errorDescription: String? {
        switch self {
        case .invalidMaximumProposals(let count):
            return "Instruction proposal generation requires a positive proposal count; received \(count)."

        case .emptyProposedInstructions(let index):
            return "Instruction proposal \(index) contains empty instructions."

        case .duplicateCandidateIdentifier(let identifier):
            return "Generated instruction candidate identifier '\(identifier.rawValue)' collides with another candidate identifier."

        case .noCandidatesProduced:
            return "Instruction proposal generation did not produce any usable realization candidates."
        }
    }
}

public struct InferenceInstructionProposalCandidateGenerator:
    InferenceRealizationCandidateGenerating,
    Sendable
{
    private struct ParsedProposal: Sendable {
        let index: Int
        let instructions: String
        let rationale: String
    }

    private let proposer: any InferenceExecuting

    public let proposalRealization: InferenceRealizationConfiguration
    public let maximumProposals: Int
    public let includeSeed: Bool
    public let seedIdentifier: InferenceRealizationCandidateIdentifier

    private init(
        proposer: any InferenceExecuting,
        proposalRealization: InferenceRealizationConfiguration,
        parsedMaximumProposals maximumProposals: Int,
        includeSeed: Bool,
        seedIdentifier: InferenceRealizationCandidateIdentifier
    ) {
        self.proposer = proposer
        self.proposalRealization = proposalRealization
        self.maximumProposals = maximumProposals
        self.includeSeed = includeSeed
        self.seedIdentifier = seedIdentifier
    }

    public static func parse(
        proposer: any InferenceExecuting,
        proposalRealization: InferenceRealizationConfiguration,
        maximumProposals: Int = 4,
        includeSeed: Bool = true,
        seedIdentifier: InferenceRealizationCandidateIdentifier = "seed"
    ) throws -> Self {
        guard maximumProposals > 0 else {
            throw InferenceInstructionProposalGeneratorError
                .invalidMaximumProposals(
                    maximumProposals
                )
        }

        if includeSeed {
            for index in 1...maximumProposals {
                let generatedIdentifier =
                    InferenceRealizationCandidateIdentifier(
                        "proposal_\(index)"
                    )

                guard generatedIdentifier != seedIdentifier else {
                    throw InferenceInstructionProposalGeneratorError
                        .duplicateCandidateIdentifier(
                            seedIdentifier
                        )
                }
            }
        }

        return Self(
            proposer: proposer,
            proposalRealization: proposalRealization,
            parsedMaximumProposals: maximumProposals,
            includeSeed: includeSeed,
            seedIdentifier: seedIdentifier
        )
    }

    public func generate<InferenceType: Inference>(
        _ inference: InferenceType.Type,
        examples: [InferenceOptimizationExample<InferenceType>],
        seed: InferenceRealizationConfiguration
    ) async throws -> [InferenceRealizationCandidate] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
        ]

        let proposalExamples = try examples.map { example in
            InferenceInstructionProposalExample(
                inputJSON: String(
                    decoding: try encoder.encode(
                        example.input
                    ),
                    as: UTF8.self
                ),
                expectedOutputJSON: String(
                    decoding: try encoder.encode(
                        example.expectedOutput
                    ),
                    as: UTF8.self
                ),
                metadata: example.metadata
            )
        }

        let proposalExecution = try await proposer.execute(
            Standard.Inferences.ProposeInferenceInstructions.self,
            input: Standard.Inferences.ProposeInferenceInstructions.Input(
                inferenceIdentifier: inference.definition.identifier.rawValue,
                inferencePurpose: inference.definition.purpose,
                seedInstructions: seed.instructions,
                examples: proposalExamples,
                requestedProposalCount: maximumProposals
            ),
            realization: proposalRealization
        )
        let proposals = try parse(
            proposalExecution.output.proposals,
            seedInstructions: seed.instructions
        )

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

        for proposal in proposals {
            var realization = seed
            realization.instructions = proposal.instructions

            candidates.append(
                InferenceRealizationCandidate(
                    identifier: InferenceRealizationCandidateIdentifier(
                        "proposal_\(proposal.index + 1)"
                    ),
                    realization: realization,
                    source: .inference_proposal,
                    generation: proposalExecution.record,
                    metadata: [
                        "proposal.index": String(
                            proposal.index
                        ),
                        "proposal.rationale": proposal.rationale,
                    ]
                )
            )
        }

        return candidates
    }

    private func parse(
        _ proposals: [InferenceInstructionProposal],
        seedInstructions: String
    ) throws -> [ParsedProposal] {
        var seenInstructions: Set<String> = []

        if includeSeed {
            seenInstructions.insert(
                normalizedInstructions(
                    seedInstructions
                )
            )
        }

        var parsed: [ParsedProposal] = []

        for (index, proposal) in proposals
            .prefix(maximumProposals)
            .enumerated()
        {
            let instructions = normalizedInstructions(
                proposal.instructions
            )

            guard !instructions.isEmpty else {
                throw InferenceInstructionProposalGeneratorError
                    .emptyProposedInstructions(
                        index
                    )
            }

            guard seenInstructions.insert(instructions).inserted else {
                continue
            }

            parsed.append(
                ParsedProposal(
                    index: index,
                    instructions: instructions,
                    rationale: proposal.rationale
                )
            )
        }

        guard includeSeed || !parsed.isEmpty else {
            throw InferenceInstructionProposalGeneratorError
                .noCandidatesProduced
        }

        return parsed
    }

    private func normalizedInstructions(
        _ instructions: String
    ) -> String {
        instructions.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }
}