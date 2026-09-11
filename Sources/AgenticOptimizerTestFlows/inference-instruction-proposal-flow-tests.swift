import AgenticInference
import AgenticOptimizer
import Foundation
import TestFlows

private struct ProposalSearchFixtureInference: AgentInference {
    typealias Input = String
    typealias Output = String

    static let definition = AgentInferenceDefinition(
        identifier: "fixture.proposal_search",
        purpose: "Transform the supplied text to uppercase."
    )
}

private struct ProposalObservation: Sendable {
    var input: ProposeInferenceInstructions.Input
    var realization: AgentInferenceRealization
}

private actor ProposalRecorder {
    private var observations: [ProposalObservation] = []

    func append(
        _ observation: ProposalObservation
    ) {
        observations.append(
            observation
        )
    }

    func snapshot() -> [ProposalObservation] {
        observations
    }
}

private struct ProposalFixtureExecutor:
    AgentInferenceExecuting,
    Sendable
{
    let recorder: ProposalRecorder

    func execute<Inference: AgentInference>(
        _ inference: Inference.Type,
        input: Inference.Input,
        realization: AgentInferenceRealization
    ) async throws -> AgentInferenceExecutionResult<Inference.Output> {
        let inputData = try JSONEncoder().encode(
            input
        )
        let proposalInput = try JSONDecoder().decode(
            ProposeInferenceInstructions.Input.self,
            from: inputData
        )

        await recorder.append(
            ProposalObservation(
                input: proposalInput,
                realization: realization
            )
        )

        let proposalSet = AgentInferenceInstructionProposalSet(
            proposals: [
                .init(
                    instructions: "identity",
                    rationale: "Preserve the baseline as a duplicate proposal."
                ),
                .init(
                    instructions: "uppercase",
                    rationale: "Transform every input to uppercase."
                ),
                .init(
                    instructions: "constant",
                    rationale: "Return a fixed value regardless of input."
                ),
            ]
        )
        let outputData = try JSONEncoder().encode(
            proposalSet
        )
        let output = try JSONDecoder().decode(
            Inference.Output.self,
            from: outputData
        )

        return AgentInferenceExecutionResult(
            output: output,
            record: AgentInferenceExecutionRecord(
                inference: inference.definition.identifier,
                strategy: realization.strategy,
                budget: realization.budget,
                metadata: [
                    "fixture": "instruction_proposal",
                ]
            )
        )
    }
}

private struct ProposalSearchFixtureExecutor:
    AgentInferenceExecuting,
    Sendable
{
    func execute<Inference: AgentInference>(
        _ inference: Inference.Type,
        input: Inference.Input,
        realization: AgentInferenceRealization
    ) async throws -> AgentInferenceExecutionResult<Inference.Output> {
        let inputData = try JSONEncoder().encode(
            input
        )
        let inputText = try JSONDecoder().decode(
            String.self,
            from: inputData
        )

        let outputText: String

        switch realization.instructions {
        case "identity":
            outputText = inputText

        case "uppercase":
            outputText = inputText.uppercased()

        case "constant":
            outputText = "ALPHA"

        default:
            throw ProposalFixtureError.unknownInstructions(
                realization.instructions
            )
        }

        let outputData = try JSONEncoder().encode(
            outputText
        )
        let output = try JSONDecoder().decode(
            Inference.Output.self,
            from: outputData
        )

        return AgentInferenceExecutionResult(
            output: output,
            record: AgentInferenceExecutionRecord(
                inference: inference.definition.identifier,
                strategy: realization.strategy,
                budget: realization.budget,
                metadata: realization.metadata
            )
        )
    }
}

private struct ProposalExactOutputObjective:
    AgentInferenceOptimizationObjective,
    Sendable
{
    let identifier: AgentInferenceOptimizationObjectiveIdentifier =
        "proposal_exact_output"

    func score<Inference: AgentInference>(
        _ inference: Inference.Type,
        example: AgentInferenceOptimizationExample<Inference>,
        result: AgentInferenceExecutionResult<Inference.Output>
    ) async throws -> AgentInferenceOptimizationScore {
        let expectedData = try JSONEncoder().encode(
            example.expectedOutput
        )
        let expected = try JSONDecoder().decode(
            String.self,
            from: expectedData
        )
        let actualData = try JSONEncoder().encode(
            result.output
        )
        let actual = try JSONDecoder().decode(
            String.self,
            from: actualData
        )

        return AgentInferenceOptimizationScore(
            value: expected == actual ? 1.0 : 0.0
        )
    }
}

private enum ProposalFixtureError:
    Error,
    Sendable
{
    case unknownInstructions(String)
}

extension AgenticOptimizerFlowTesting {
    static func runInferenceInstructionProposal()
        async throws
        -> [TestFlowDiagnostic]
    {
        let examples: [
            AgentInferenceOptimizationExample<ProposalSearchFixtureInference>
        ] = [
            .init(
                input: "alpha",
                expectedOutput: "ALPHA",
                metadata: [
                    "example": "one",
                ]
            ),
            .init(
                input: "beta",
                expectedOutput: "BETA",
                metadata: [
                    "example": "two",
                ]
            ),
        ]
        let seed = AgentInferenceRealization(
            strategy: .direct,
            modelSelection: .executor,
            instructions: "identity",
            budget: .singleAttempt,
            metadata: [
                "seed": "preserved",
            ]
        )
        let proposalRealization = AgentInferenceRealization(
            strategy: .native_reasoning,
            modelSelection: .executor,
            instructions: "Propose diverse complete instruction alternatives.",
            budget: .singleAttempt,
            metadata: [
                "role": "optimizer_proposer",
            ]
        )

        let recorder = ProposalRecorder()
        let generator = AgentInferenceInstructionProposalCandidateGenerator(
            proposer: ProposalFixtureExecutor(
                recorder: recorder
            ),
            proposalRealization: proposalRealization,
            maximumProposals: 3,
            includeSeed: true,
            seedIdentifier: "baseline"
        )
        let search = AgentInferenceRealizationSearch(
            executor: ProposalSearchFixtureExecutor(),
            objective: ProposalExactOutputObjective()
        )

        let result = try await search.optimize(
            ProposalSearchFixtureInference.self,
            examples: examples,
            seed: seed,
            generator: generator
        )
        let observations = await recorder.snapshot()

        try Expect.equal(
            observations.count,
            1,
            "generated search performs one semantic instruction-proposal inference"
        )
        try Expect.equal(
            observations[0].input.inferenceIdentifier,
            ProposalSearchFixtureInference.definition.identifier.rawValue,
            "proposal inference receives the semantic inference identity"
        )
        try Expect.equal(
            observations[0].input.inferencePurpose,
            ProposalSearchFixtureInference.definition.purpose,
            "proposal inference receives the semantic inference purpose"
        )
        try Expect.equal(
            observations[0].input.seedInstructions,
            "identity",
            "proposal inference receives current seed instructions"
        )
        try Expect.equal(
            observations[0].input.examples.count,
            2,
            "proposal inference receives encoded optimization examples"
        )
        try Expect.equal(
            observations[0].input.requestedProposalCount,
            3,
            "proposal inference receives the requested proposal budget"
        )
        try Expect.equal(
            observations[0].realization.strategy,
            .native_reasoning,
            "instruction proposal uses its independently configured inference realization"
        )

        try Expect.equal(
            result.candidates.count,
            3,
            "duplicate seed-equivalent proposal is removed before evaluation"
        )
        try Expect.equal(
            result.trials.count,
            6,
            "search evaluates seed plus distinct proposed candidates against every example"
        )
        try Expect.equal(
            result.selectedCandidate.identifier,
            AgentInferenceRealizationCandidateIdentifier(
                "proposal_2"
            ),
            "optimizer selects the best inference-proposed instruction candidate"
        )
        try Expect.equal(
            result.selectedCandidate.source,
            .inference_proposal,
            "selected realization retains typed inference-proposal provenance"
        )
        try Expect.equal(
            result.selectedCandidate.realization.instructions,
            "uppercase",
            "selected proposal is directly reusable as an inference realization"
        )
        try Expect.equal(
            result.selectedCandidate.realization.metadata[
                "seed"
            ],
            "preserved",
            "proposal generation varies instructions without discarding seed realization metadata"
        )
        try Expect.equal(
            result.selectedCandidate.generation?.inference,
            ProposeInferenceInstructions.definition.identifier,
            "generated candidate preserves the proposal inference execution record"
        )
        try Expect.equal(
            result.selectedCandidate.generation?.strategy,
            .native_reasoning,
            "generation provenance preserves the proposal inference strategy"
        )
        try Expect.equal(
            result.selectedCandidate.metadata[
                "proposal.rationale"
            ],
            "Transform every input to uppercase.",
            "candidate retains proposal rationale as supplementary provenance"
        )

        let encoded = try JSONEncoder().encode(
            result
        )
        let decoded = try JSONDecoder().decode(
            AgentInferenceOptimizationResult.self,
            from: encoded
        )

        try Expect.equal(
            decoded,
            result,
            "inference-generated optimization provenance survives codec round trip"
        )

        return [
            .field(
                "proposal_inference",
                ProposeInferenceInstructions.definition.identifier.rawValue
            ),
            .field(
                "proposal_strategy",
                observations[0].realization.strategy.rawValue
            ),
            .field(
                "candidates",
                String(result.candidates.count)
            ),
            .field(
                "trials",
                String(result.trials.count)
            ),
            .field(
                "selected",
                result.selectedCandidate.identifier.rawValue
            ),
            .field(
                "source",
                result.selectedCandidate.source.rawValue
            ),
            .field(
                "generation_recorded",
                String(result.selectedCandidate.generation != nil)
            ),
        ]
    }
}
