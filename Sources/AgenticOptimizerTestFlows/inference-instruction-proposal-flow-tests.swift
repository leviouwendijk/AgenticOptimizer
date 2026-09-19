import Agentic
import AgenticInference
import AgenticOptimizer
import Foundation
import TestFlows

private struct ProposalSearchFixtureInference: Inference {
    typealias Input = String
    typealias Output = String

    static let definition = InferenceDefinition(
        identifier: "fixture.proposal_search",
        purpose: "Transform the supplied text to uppercase."
    )
}

private struct ProposalObservation: Sendable {
    var input: Standard.Inferences.ProposeInferenceInstructions.Input
    var realization: InferenceRealizationConfiguration
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
    InferenceExecuting,
    Sendable
{
    let recorder: ProposalRecorder

    func execute(
        _ invocation: InferenceInvocation
    ) async throws -> InferenceInvocationResult {
        let inference = invocation
        let realization = invocation.realization
        let inputData = invocation.input
        let proposalInput = try JSONDecoder().decode(
            Standard.Inferences.ProposeInferenceInstructions.Input.self,
            from: inputData
        )

        await recorder.append(
            ProposalObservation(
                input: proposalInput,
                realization: realization
            )
        )

        let proposalSet = Standard.Inferences.ProposeInferenceInstructions.Output(
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
        return InferenceInvocationResult(
            output: outputData,
            record: InferenceExecutionRecord(
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
    InferenceExecuting,
    Sendable
{
    func execute(
        _ invocation: InferenceInvocation
    ) async throws -> InferenceInvocationResult {
        let inference = invocation
        let realization = invocation.realization
        let inputData = invocation.input
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
        return InferenceInvocationResult(
            output: outputData,
            record: InferenceExecutionRecord(
                inference: inference.definition.identifier,
                strategy: realization.strategy,
                budget: realization.budget,
                metadata: realization.metadata
            )
        )
    }
}

private struct ProposalExactOutputObjective:
    InferenceOptimizationObjective,
    Sendable
{
    let identifier: InferenceOptimizationObjectiveIdentifier =
        "proposal_exact_output"

    func score<InferenceType: Inference>(
        _ inference: InferenceType.Type,
        example: InferenceOptimizationExample<InferenceType>,
        result: InferenceExecutionResult<InferenceType.Output>
    ) async throws -> InferenceOptimizationScore {
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

        return try InferenceOptimizationScore(
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

extension OptimizerFlowTesting {
    static func runInferenceInstructionProposal()
        async throws
        -> [TestFlowDiagnostic]
    {
        let examples: [
            InferenceOptimizationExample<ProposalSearchFixtureInference>
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
        let seed = InferenceRealizationConfiguration(
            strategy: .direct,
            instructions: "identity",
            budget: .singleAttempt,
            metadata: [
                "seed": "preserved",
            ]
        )
        let proposalRealization = InferenceRealizationConfiguration(
            strategy: .native_reasoning,
            instructions: "Propose diverse complete instruction alternatives.",
            budget: .singleAttempt,
            metadata: [
                "role": "optimizer_proposer",
            ]
        )

        let recorder = ProposalRecorder()
        let generator = try InferenceInstructionProposalCandidateGenerator.parse(
            proposer: ProposalFixtureExecutor(
                recorder: recorder
            ),
            proposalRealization: proposalRealization,
            maximumProposals: 3,
            includeSeed: true,
            seedIdentifier: "baseline"
        )
        var invalidMaximumRejected = false

        do {
            _ = try InferenceInstructionProposalCandidateGenerator.parse(
                proposer: ProposalFixtureExecutor(
                    recorder: recorder
                ),
                proposalRealization: proposalRealization,
                maximumProposals: 0
            )
        } catch InferenceInstructionProposalGeneratorError
            .invalidMaximumProposals {
            invalidMaximumRejected = true
        }

        try Expect.equal(
            invalidMaximumRejected,
            true,
            "proposal generator parsing rejects non-positive proposal limits before execution"
        )

        var identifierCollisionRejected = false

        do {
            _ = try InferenceInstructionProposalCandidateGenerator.parse(
                proposer: ProposalFixtureExecutor(
                    recorder: recorder
                ),
                proposalRealization: proposalRealization,
                maximumProposals: 3,
                includeSeed: true,
                seedIdentifier: "proposal_1"
            )
        } catch InferenceInstructionProposalGeneratorError
            .duplicateCandidateIdentifier {
            identifierCollisionRejected = true
        }

        try Expect.equal(
            identifierCollisionRejected,
            true,
            "proposal generator parsing rejects seed identities reserved for generated proposals"
        )

        let search = InferenceRealizationSearch(
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
            InferenceRealizationCandidateIdentifier(
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
            Standard.Inferences.ProposeInferenceInstructions.definition.identifier,
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
            InferenceOptimizationResult.self,
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
                Standard.Inferences.ProposeInferenceInstructions.definition.identifier.rawValue
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
                "invalid_maximum_rejected",
                String(invalidMaximumRejected)
            ),
            .field(
                "identifier_collision_rejected",
                String(identifierCollisionRejected)
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