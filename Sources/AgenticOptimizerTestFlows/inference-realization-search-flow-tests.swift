import Agentic
import AgenticInference
import AgenticOptimizer
import Foundation
import TestFlows

private struct OptimizerFixtureInference: Inference {
    typealias Input = String
    typealias Output = String

    static let definition = InferenceDefinition(
        identifier: "fixture.optimizer_search",
        purpose: "Prove deterministic realization optimization."
    )
}

private struct OptimizerFixtureExecutor:
    InferenceExecuting,
    Sendable
{
    func execute<InferenceType: Inference>(
        _ inference: InferenceType.Type,
        input: InferenceType.Input,
        realization: InferenceRealizationConfiguration,
        context: InferenceExecutionContext
    ) async throws -> InferenceExecutionResult<InferenceType.Output> {
        _ = context
        let inputData = try JSONEncoder().encode(
            input
        )
        let inputText = try JSONDecoder().decode(
            String.self,
            from: inputData
        )

        let outputText: String

        switch realization.instructions {
        case "constant":
            outputText = "ALPHA"

        case "identity":
            outputText = inputText

        case "uppercase":
            outputText = inputText.uppercased()

        default:
            throw OptimizerFixtureError.unknownInstructions(
                realization.instructions
            )
        }

        let outputData = try JSONEncoder().encode(
            outputText
        )
        let output = try JSONDecoder().decode(
            InferenceType.Output.self,
            from: outputData
        )

        return InferenceExecutionResult(
            output: output,
            record: InferenceExecutionRecord(
                inference: inference.definition.identifier,
                strategy: realization.strategy,
                budget: realization.budget,
                metadata: realization.metadata
            )
        )
    }
}

private struct ExactOutputObjective:
    InferenceOptimizationObjective,
    Sendable
{
    let identifier: InferenceOptimizationObjectiveIdentifier =
        "exact_output"

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
            value: expected == actual ? 1.0 : 0.0,
            metadata: [
                "expected": expected,
                "actual": actual,
            ]
        )
    }
}

private enum OptimizerFixtureError:
    Error,
    Sendable
{
    case unknownInstructions(String)
}

enum OptimizerFlowTesting {
    static func runInferenceRealizationSearch()
        async throws
        -> [TestFlowDiagnostic]
    {
        let examples: [
            InferenceOptimizationExample<OptimizerFixtureInference>
        ] = [
            .init(
                input: "alpha",
                expectedOutput: "ALPHA"
            ),
            .init(
                input: "beta",
                expectedOutput: "BETA"
            ),
        ]

        let candidates: [InferenceRealizationCandidate] = [
            .init(
                identifier: "constant",
                realization: InferenceRealizationConfiguration(
                    strategy: .direct,
                    instructions: "constant",
                    budget: .singleAttempt,
                    metadata: [
                        "candidate": "constant",
                    ]
                )
            ),
            .init(
                identifier: "identity",
                realization: InferenceRealizationConfiguration(
                    strategy: .direct,
                    instructions: "identity",
                    budget: .singleAttempt,
                    metadata: [
                        "candidate": "identity",
                    ]
                )
            ),
            .init(
                identifier: "uppercase_first",
                realization: InferenceRealizationConfiguration(
                    strategy: .direct,
                    instructions: "uppercase",
                    budget: .singleAttempt,
                    metadata: [
                        "candidate": "uppercase_first",
                    ]
                )
            ),
            .init(
                identifier: "uppercase_second",
                realization: InferenceRealizationConfiguration(
                    strategy: .direct,
                    instructions: "uppercase",
                    budget: .singleAttempt,
                    metadata: [
                        "candidate": "uppercase_second",
                    ]
                )
            ),
        ]

        let search = InferenceRealizationSearch(
            executor: OptimizerFixtureExecutor(),
            objective: ExactOutputObjective()
        )
        let result = try await search.optimize(
            OptimizerFixtureInference.self,
            examples: examples,
            candidates: candidates
        )

        try Expect.equal(
            result.inference,
            OptimizerFixtureInference.definition.identifier,
            "optimizer preserves semantic inference identity"
        )
        try Expect.equal(
            result.objective,
            ExactOutputObjective().identifier,
            "optimizer records objective identity"
        )
        try Expect.equal(
            result.candidates.count,
            4,
            "optimizer records every supplied realization candidate"
        )
        try Expect.equal(
            result.trials.count,
            8,
            "optimizer evaluates every candidate against every example"
        )
        try Expect.equal(
            result.candidates[0].meanScore,
            0.5,
            "constant candidate succeeds on only one example"
        )
        try Expect.equal(
            result.candidates[1].meanScore,
            0.0,
            "identity candidate fails uppercase objective"
        )
        try Expect.equal(
            result.candidates[2].meanScore,
            1.0,
            "uppercase candidate maximizes exact-output objective"
        )
        try Expect.equal(
            result.candidates[3].meanScore,
            1.0,
            "equally good later candidate produces a tie"
        )
        try Expect.equal(
            result.selectedCandidate.identifier,
            InferenceRealizationCandidateIdentifier(
                "uppercase_first"
            ),
            "optimizer uses stable first-candidate tie breaking"
        )
        try Expect.equal(
            result.candidates[2].trialIndexes,
            [
                4,
                5,
            ],
            "candidate result preserves global trial provenance"
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
            "optimization result and execution provenance survive codec round trip"
        )

        var emptyCandidatesRejected = false

        do {
            _ = try await search.optimize(
                OptimizerFixtureInference.self,
                examples: examples,
                candidates: []
            )
        } catch InferenceOptimizationProblemParsingError.noCandidates {
            emptyCandidatesRejected = true
        }

        try Expect.equal(
            emptyCandidatesRejected,
            true,
            "optimizer rejects an empty realization search space"
        )

        var emptyExamplesRejected = false

        do {
            _ = try await search.optimize(
                OptimizerFixtureInference.self,
                examples: [],
                candidates: candidates
            )
        } catch InferenceOptimizationProblemParsingError.noExamples {
            emptyExamplesRejected = true
        }

        try Expect.equal(
            emptyExamplesRejected,
            true,
            "optimizer rejects optimization without evaluation examples"
        )

        return [
            .field(
                "inference",
                result.inference.rawValue
            ),
            .field(
                "objective",
                result.objective.rawValue
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
                "selected_score",
                String(result.candidates[2].meanScore)
            ),
            .field(
                "stable_tie_break",
                "true"
            ),
        ]
    }
}