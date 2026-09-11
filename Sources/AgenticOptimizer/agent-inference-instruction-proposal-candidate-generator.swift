import AgenticInference
import Foundation

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
    private let proposer: any AgentInferenceExecuting

    public var proposalRealization: AgentInferenceRealization
    public var maximumProposals: Int
    public var includeSeed: Bool
    public var seedIdentifier: AgentInferenceRealizationCandidateIdentifier

    public init(
        proposer: any AgentInferenceExecuting,
        proposalRealization: AgentInferenceRealization,
        maximumProposals: Int = 4,
        includeSeed: Bool = true,
        seedIdentifier: AgentInferenceRealizationCandidateIdentifier = "seed"
    ) {
        self.proposer = proposer
        self.proposalRealization = proposalRealization
        self.maximumProposals = maximumProposals
        self.includeSeed = includeSeed
        self.seedIdentifier = seedIdentifier
    }

    public func generate<Inference: AgentInference>(
        _ inference: Inference.Type,
        examples: [AgentInferenceOptimizationExample<Inference>],
        seed: AgentInferenceRealization
    ) async throws -> [AgentInferenceRealizationCandidate] {
        guard maximumProposals > 0 else {
            throw AgentInferenceInstructionProposalGeneratorError
                .invalidMaximumProposals(
                    maximumProposals
                )
        }

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

        var candidates: [AgentInferenceRealizationCandidate] = []
        var identifiers: Set<AgentInferenceRealizationCandidateIdentifier> = []
        var seenInstructions: Set<String> = []

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

            seenInstructions.insert(
                normalizedInstructions(
                    seed.instructions
                )
            )
        }

        for (index, proposal) in proposalExecution.output.proposals
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

            let identifier = AgentInferenceRealizationCandidateIdentifier(
                "proposal_\(index + 1)"
            )

            try insertIdentifier(
                identifier,
                into: &identifiers
            )

            var realization = seed
            realization.instructions = instructions

            candidates.append(
                AgentInferenceRealizationCandidate(
                    identifier: identifier,
                    realization: realization,
                    source: .inference_proposal,
                    generation: proposalExecution.record,
                    metadata: [
                        "proposal.index": String(index),
                        "proposal.rationale": proposal.rationale,
                    ]
                )
            )
        }

        guard !candidates.isEmpty else {
            throw AgentInferenceInstructionProposalGeneratorError
                .noCandidatesProduced
        }

        return candidates
    }

    private func normalizedInstructions(
        _ instructions: String
    ) -> String {
        instructions.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private func insertIdentifier(
        _ identifier: AgentInferenceRealizationCandidateIdentifier,
        into identifiers: inout Set<AgentInferenceRealizationCandidateIdentifier>
    ) throws {
        guard identifiers.insert(identifier).inserted else {
            throw AgentInferenceInstructionProposalGeneratorError
                .duplicateCandidateIdentifier(
                    identifier
                )
        }
    }
}
