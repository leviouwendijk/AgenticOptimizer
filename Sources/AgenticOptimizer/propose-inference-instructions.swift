import Agentic
import AgenticInference
import Schema
import Macros

public struct InferenceInstructionProposalExample:
    Sendable,
    Codable,
    Hashable
{
    public var inputJSON: String
    public var expectedOutputJSON: String
    public var metadata: [String: String]

    public init(
        inputJSON: String,
        expectedOutputJSON: String,
        metadata: [String: String] = [:]
    ) {
        self.inputJSON = inputJSON
        self.expectedOutputJSON = expectedOutputJSON
        self.metadata = metadata
    }
}

@JSONSchema
public struct InferenceInstructionProposal:
    Sendable,
    Codable,
    Hashable
{
    /// Complete instructions that can replace the seed realization instructions.
    public var instructions: String

    /// Brief explanation of the intended improvement.
    public var rationale: String

    public init(
        instructions: String,
        rationale: String
    ) {
        self.instructions = instructions
        self.rationale = rationale
    }
}

@JSONSchema
public struct InferenceInstructionProposalSet:
    Sendable,
    Codable,
    Hashable
{
    /// Distinct instruction alternatives worth evaluating against the supplied examples.
    public var proposals: [InferenceInstructionProposal]

    public init(
        proposals: [InferenceInstructionProposal]
    ) {
        self.proposals = proposals
    }
}

extension Standard.Inferences {
    @Inference
    public struct ProposeInferenceInstructions {
        public struct Input:
            Sendable,
            Codable,
            Hashable
        {
            public var inferenceIdentifier: String
            public var inferencePurpose: String
            public var seedInstructions: String
            public var examples: [InferenceInstructionProposalExample]
            public var requestedProposalCount: Int

            public init(
                inferenceIdentifier: String,
                inferencePurpose: String,
                seedInstructions: String,
                examples: [InferenceInstructionProposalExample],
                requestedProposalCount: Int
            ) {
                self.inferenceIdentifier = inferenceIdentifier
                self.inferencePurpose = inferencePurpose
                self.seedInstructions = seedInstructions
                self.examples = examples
                self.requestedProposalCount = requestedProposalCount
            }
        }

        public typealias Output = InferenceInstructionProposalSet

        public static let purpose =
            "Propose distinct complete instruction variants for a semantic inference so an optimizer can evaluate them against typed examples."
    }
}
