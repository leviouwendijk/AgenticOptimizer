import AgenticInference
import Foundation
import Primitives

public enum AgentInferenceInstructionProposalGeneratorError:
    Error,
    Sendable,
    LocalizedError
{
    case invalidMaximumProposals(Int)
    case emptyProposedInstructions(Int)
    case duplicateCandidateIdentifier(
        AgentInferenceRealizationCandidateIdentifier
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

public struct AgentInferenceInstructionProposalCandidateGenerator:
    AgentInferenceRealizationCandidateGenerating,
    Sendable
{
    private struct ParsedProposal: Sendable {
        let index: Int
        let instructions: String
        let rationale: String
    }

    private let proposer: any AgentInferenceExecuting

    public let proposalRealization: AgentInferenceRealization
    public let maximumProposals: Int
    public let includeSeed: Bool
    public let seedIdentifier: AgentInferenceRealizationCandidateIdentifier

    private init(
        proposer: any AgentInferenceExecuting,
        proposalRealization: AgentInferenceRealization,
        parsedMaximumProposals maximumProposals: Int,
        includeSeed: Bool,
        seedIdentifier: AgentInferenceRealizationCandidateIdentifier
    ) {
        self.proposer = proposer
        self.proposalRealization = proposalRealization
        self.maximumProposals = maximumProposals
        self.includeSeed = includeSeed
        self.seedIdentifier = seedIdentifier
    }

    public static func parse(
        proposer: any AgentInferenceExecuting,
        proposalRealization: AgentInferenceRealization,
        maximumProposals: Int = 4,
        includeSeed: Bool = true,
        seedIdentifier: AgentInferenceRealizationCandidateIdentifier = "seed"
    ) throws -> Self {
        guard maximumProposals > 0 else {
            throw AgentInferenceInstructionProposalGeneratorError
                .invalidMaximumProposals(
                    maximumProposals
                )
        }

        if includeSeed {
            for index in 1...maximumProposals {
                let generatedIdentifier =
                    AgentInferenceRealizationCandidateIdentifier(
                        "proposal_\(index)"
                    )

                guard generatedIdentifier != seedIdentifier else {
                    throw AgentInferenceInstructionProposalGeneratorError
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

    public func generate<Inference: AgentInference>(
        _ inference: Inference.Type,
        examples: [AgentInferenceOptimizationExample<Inference>],
        seed: AgentInferenceRealization
    ) async throws -> [AgentInferenceRealizationCandidate] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
        ]

        let proposalExamples = try examples.map { example in
            AgentInferenceInstructionProposalExample(
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
            ProposeInferenceInstructions.self,
            input: ProposeInferenceInstructions.Input(
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

        for proposal in proposals {
            var realization = seed
            realization.instructions = proposal.instructions

            candidates.append(
                AgentInferenceRealizationCandidate(
                    identifier: AgentInferenceRealizationCandidateIdentifier(
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
        _ proposals: [AgentInferenceInstructionProposal],
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
                throw AgentInferenceInstructionProposalGeneratorError
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
            throw AgentInferenceInstructionProposalGeneratorError
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
