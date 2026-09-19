import Agentic
import AgenticInference
import AgenticOptimizer
import Foundation
import Primitives
import TestFlows

private struct BootstrapFixtureInference: Inference {
    typealias Input = String
    typealias Output = String

    static let definition = InferenceDefinition(
        identifier: "fixture.demonstration_bootstrap",
        purpose: "Transform supplied text to uppercase."
    )
}

private struct BootstrapFixtureExecutor:
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

        if realization.metadata["role"] == "teacher" {
            if inputText == "beta" {
                outputText = inputText
            } else {
                outputText = inputText.uppercased()
            }
        } else if realization.demonstrations.count >= 2 {
            outputText = inputText.uppercased()
        } else {
            outputText = inputText
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
                metadata: [
                    "fixture.input": inputText,
                    "fixture.role": realization.metadata["role"] ?? "student",
                ]
            )
        )
    }
}

private struct BootstrapExactObjective:
    InferenceOptimizationObjective,
    Sendable
{
    let identifier: InferenceOptimizationObjectiveIdentifier =
        "bootstrap_exact_output"

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

extension OptimizerFlowTesting {
    static func runDemonstrationBootstrap()
        async throws
        -> [TestFlowDiagnostic]
    {
        let examples: [
            InferenceOptimizationExample<BootstrapFixtureInference>
        ] = [
            .init(
                input: "alpha",
                expectedOutput: "ALPHA"
            ),
            .init(
                input: "beta",
                expectedOutput: "BETA"
            ),
            .init(
                input: "gamma",
                expectedOutput: "GAMMA"
            ),
        ]

        let seed = InferenceRealizationConfiguration(
            strategy: .direct,
            instructions: "Use successful demonstrations to infer the transformation.",
            budget: .singleAttempt,
            metadata: [
                "seed_marker": "preserved",
            ]
        )
        let teacher = InferenceRealizationConfiguration(
            strategy: .native_reasoning,
            instructions: "Produce the best answer for this training example.",
            budget: .singleAttempt,
            metadata: [
                "role": "teacher",
            ]
        )
        let objective = BootstrapExactObjective()
        let generator = try InferenceDemonstrationBootstrapGenerator.parse(
            executor: BootstrapFixtureExecutor(),
            objective: objective,
            teacher: teacher,
            minimumScore: 1.0,
            includeSeed: true,
            seedIdentifier: "baseline",
            bootstrapIdentifier: "bootstrapped"
        )

        let generated = try await generator.generate(
            BootstrapFixtureInference.self,
            examples: examples,
            seed: seed
        )

        try Expect.equal(
            generated.count,
            2,
            "bootstrap generator emits baseline and one accumulated bootstrap candidate"
        )
        try Expect.equal(
            generated[1].source,
            .demonstration_bootstrap,
            "generated realization records typed bootstrap provenance"
        )
        try Expect.equal(
            generated[1].realization.demonstrations.count,
            2,
            "only successful teacher executions become demonstrations"
        )
        try Expect.equal(
            generated[1].realization.instructions,
            seed.instructions,
            "bootstrapping preserves seed instructions"
        )
        try Expect.equal(
            generated[1].realization.strategy,
            seed.strategy,
            "bootstrapping preserves student strategy"
        )
        try Expect.equal(
            generated[1].realization.metadata[
                "seed_marker"
            ],
            "preserved",
            "bootstrapping preserves seed realization metadata"
        )

        let bootstrap = try Expect.notNil(
            generated[1].bootstrap,
            "bootstrapped candidate preserves typed bootstrap record"
        )

        try Expect.equal(
            bootstrap.inference,
            BootstrapFixtureInference.definition.identifier,
            "bootstrap record preserves semantic inference identity"
        )
        try Expect.equal(
            bootstrap.objective,
            objective.identifier,
            "bootstrap record preserves objective identity"
        )
        try Expect.equal(
            bootstrap.teacher,
            teacher,
            "bootstrap record preserves the exact teacher realization"
        )
        try Expect.equal(
            bootstrap.trials.count,
            3,
            "bootstrap records every teacher execution"
        )
        try Expect.equal(
            bootstrap.acceptedCount,
            2,
            "bootstrap records the number of accepted executions"
        )
        try Expect.equal(
            bootstrap.trials[0].accepted,
            true,
            "successful teacher execution is accepted"
        )
        try Expect.equal(
            bootstrap.trials[1].accepted,
            false,
            "failed teacher execution is rejected"
        )
        try Expect.equal(
            bootstrap.trials[2].accepted,
            true,
            "later successful teacher execution is accepted"
        )
        try Expect.equal(
            bootstrap.trials[0].demonstration.input,
            .string("alpha"),
            "bootstrap demonstration preserves the actual typed example input"
        )
        try Expect.equal(
            bootstrap.trials[0].demonstration.output,
            .string("ALPHA"),
            "bootstrap demonstration preserves the teacher execution output"
        )
        try Expect.equal(
            bootstrap.trials[1].demonstration.output,
            .string("beta"),
            "rejected trial proves bootstrap uses actual teacher output rather than gold expected output"
        )
        try Expect.equal(
            bootstrap.trials[1].execution.metadata[
                "fixture.input"
            ],
            "beta",
            "bootstrap retains exact execution provenance for rejected trials"
        )

        let search = InferenceRealizationSearch(
            executor: BootstrapFixtureExecutor(),
            objective: objective
        )
        let result = try await search.optimize(
            BootstrapFixtureInference.self,
            examples: examples,
            seed: seed,
            generator: generator
        )

        try Expect.equal(
            result.candidates.count,
            2,
            "search evaluates baseline and bootstrapped realization"
        )
        try Expect.equal(
            result.trials.count,
            6,
            "search evaluates both realizations against every optimization example"
        )
        try Expect.equal(
            result.candidates[0].meanScore,
            0.0,
            "student baseline fails before demonstration bootstrapping"
        )
        try Expect.equal(
            result.candidates[1].meanScore,
            1.0,
            "bootstrapped demonstrations improve the student across the evaluation set"
        )
        try Expect.equal(
            result.selectedCandidate.identifier,
            InferenceRealizationCandidateIdentifier(
                "bootstrapped"
            ),
            "optimizer selects the improved bootstrapped realization"
        )
        try Expect.equal(
            result.selectedCandidate.source,
            .demonstration_bootstrap,
            "selected candidate retains bootstrap provenance"
        )
        try Expect.equal(
            result.selectedCandidate.bootstrap?.acceptedCount,
            2,
            "selected optimization result retains bootstrap execution provenance"
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
            "bootstrapped optimization provenance survives codec round trip"
        )

        var collisionRejected = false

        do {
            _ = try InferenceDemonstrationBootstrapGenerator.parse(
                executor: BootstrapFixtureExecutor(),
                objective: objective,
                teacher: teacher,
                minimumScore: 1.0,
                includeSeed: true,
                seedIdentifier: "same",
                bootstrapIdentifier: "same"
            )
        } catch InferenceDemonstrationBootstrapGeneratorError
            .duplicateCandidateIdentifier {
            collisionRejected = true
        }

        try Expect.equal(
            collisionRejected,
            true,
            "bootstrap configuration parsing rejects ambiguous candidate identities before execution"
        )

        var nonFiniteMinimumRejected = false

        do {
            _ = try InferenceDemonstrationBootstrapGenerator.parse(
                executor: BootstrapFixtureExecutor(),
                objective: objective,
                teacher: teacher,
                minimumScore: .infinity,
                includeSeed: false
            )
        } catch InferenceOptimizationScoreParsingError
            .nonFinite {
            nonFiniteMinimumRejected = true
        }

        try Expect.equal(
            nonFiniteMinimumRejected,
            true,
            "bootstrap configuration parses its minimum score into the finite score representation"
        )

        return [
            .field(
                "teacher_strategy",
                teacher.strategy.rawValue
            ),
            .field(
                "teacher_trials",
                String(bootstrap.trials.count)
            ),
            .field(
                "accepted",
                String(bootstrap.acceptedCount)
            ),
            .field(
                "generated",
                String(generated.count)
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
                "gold_output_not_copied",
                String(
                    bootstrap.trials[1].demonstration.output == .string("beta")
                )
            ),
            .field(
                "collision_rejected",
                String(collisionRejected)
            ),
            .field(
                "nonfinite_minimum_rejected",
                String(nonFiniteMinimumRejected)
            ),
        ]
    }
}