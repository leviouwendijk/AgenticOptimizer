import AgenticInference
import AgenticOptimizer
import Foundation
import Primitives
import TestFlows

private struct DemonstrationFixtureInference: AgentInference {
    typealias Input = String
    typealias Output = String

    static let definition = AgentInferenceDefinition(
        identifier: "fixture.demonstration_search",
        purpose: "Prove demonstration sets can be optimized independently from other realization fields."
    )
}

private struct DemonstrationFixtureExecutor:
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

        let behavior = realization.demonstrations
            .last?
            .metadata["fixture.behavior"]

        let outputText: String

        switch behavior {
        case "uppercase":
            outputText = inputText.uppercased()

        case "constant":
            outputText = "ALPHA"

        case .none:
            outputText = inputText

        default:
            throw DemonstrationFixtureError.unknownBehavior(
                behavior ?? "missing"
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
                metadata: [
                    "fixture.demonstrations": String(
                        realization.demonstrations.count
                    ),
                ]
            )
        )
    }
}

private struct DemonstrationExactObjective:
    AgentInferenceOptimizationObjective,
    Sendable
{
    let identifier: AgentInferenceOptimizationObjectiveIdentifier =
        "demonstration_exact_output"

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

private enum DemonstrationFixtureError:
    Error,
    Sendable
{
    case unknownBehavior(String)
}

extension AgenticOptimizerFlowTesting {
    static func runDemonstrationOptimization()
        async throws
        -> [TestFlowDiagnostic]
    {
        let examples: [
            AgentInferenceOptimizationExample<DemonstrationFixtureInference>
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

        let seed = AgentInferenceRealization(
            strategy: .direct,
            modelSelection: .executor,
            instructions: "Use the supplied demonstrations to perform the transformation.",
            budget: .singleAttempt,
            demonstrations: [],
            metadata: [
                "seed_marker": "preserved",
            ]
        )

        let constantDemonstration = AgentInferenceDemonstration(
            input: .string("alpha"),
            output: .string("ALPHA"),
            metadata: [
                "fixture.behavior": "constant",
            ]
        )
        let uppercaseDemonstration = AgentInferenceDemonstration(
            input: .string("example"),
            output: .string("EXAMPLE"),
            metadata: [
                "fixture.behavior": "uppercase",
            ]
        )

        let generator = AgentInferenceDemonstrationVariantGenerator(
            variants: [
                .init(
                    identifier: "constant_demo",
                    demonstrations: [
                        constantDemonstration,
                    ],
                    metadata: [
                        "variant": "constant",
                    ]
                ),
                .init(
                    identifier: "uppercase_demo",
                    demonstrations: [
                        uppercaseDemonstration,
                    ],
                    metadata: [
                        "variant": "uppercase",
                    ]
                ),
            ],
            includeSeed: true,
            seedIdentifier: "baseline"
        )

        let generated = try await generator.generate(
            DemonstrationFixtureInference.self,
            examples: examples,
            seed: seed
        )

        try Expect.equal(
            generated.count,
            3,
            "demonstration generator emits baseline and configured variants"
        )
        try Expect.equal(
            generated[0].source,
            .seed,
            "baseline preserves seed provenance"
        )
        try Expect.equal(
            generated[1].source,
            .demonstration_variant,
            "generated candidate records typed demonstration provenance"
        )
        try Expect.equal(
            generated[2].realization.demonstrations,
            [
                uppercaseDemonstration,
            ],
            "demonstration generation replaces the seed demonstration set"
        )
        try Expect.equal(
            generated[2].realization.instructions,
            seed.instructions,
            "demonstration generation preserves instructions"
        )
        try Expect.equal(
            generated[2].realization.strategy,
            seed.strategy,
            "demonstration generation preserves inference strategy"
        )
        try Expect.equal(
            generated[2].realization.modelSelection,
            seed.modelSelection,
            "demonstration generation preserves model selection"
        )
        try Expect.equal(
            generated[2].realization.budget,
            seed.budget,
            "demonstration generation preserves inference budget"
        )
        try Expect.equal(
            generated[2].realization.generation,
            seed.generation,
            "demonstration generation preserves generation configuration"
        )
        try Expect.equal(
            generated[2].realization.metadata[
                "seed_marker"
            ],
            "preserved",
            "demonstration generation preserves realization metadata"
        )
        try Expect.equal(
            generated[2].metadata[
                "variant"
            ],
            "uppercase",
            "candidate metadata remains separate from realization metadata"
        )

        let search = AgentInferenceRealizationSearch(
            executor: DemonstrationFixtureExecutor(),
            objective: DemonstrationExactObjective()
        )
        let result = try await search.optimize(
            DemonstrationFixtureInference.self,
            examples: examples,
            seed: seed,
            generator: generator
        )

        try Expect.equal(
            result.candidates.count,
            3,
            "search evaluates baseline plus every demonstration variant"
        )
        try Expect.equal(
            result.trials.count,
            6,
            "demonstration search evaluates every candidate against every example"
        )
        try Expect.equal(
            result.candidates[0].meanScore,
            0.0,
            "baseline without demonstrations fails the uppercase objective"
        )
        try Expect.equal(
            result.candidates[1].meanScore,
            0.5,
            "misleading demonstration succeeds on only one example"
        )
        try Expect.equal(
            result.candidates[2].meanScore,
            1.0,
            "useful demonstration maximizes the objective"
        )
        try Expect.equal(
            result.selectedCandidate.identifier,
            AgentInferenceRealizationCandidateIdentifier(
                "uppercase_demo"
            ),
            "optimizer selects the best demonstration set"
        )
        try Expect.equal(
            result.selectedCandidate.source,
            .demonstration_variant,
            "selected realization retains demonstration-variant provenance"
        )
        try Expect.equal(
            result.selectedCandidate.realization.demonstrations,
            [
                uppercaseDemonstration,
            ],
            "optimization result contains the reusable selected demonstration set"
        )

        var duplicateRejected = false

        do {
            _ = try await AgentInferenceDemonstrationVariantGenerator(
                variants: [
                    .init(
                        identifier: "duplicate",
                        demonstrations: []
                    ),
                    .init(
                        identifier: "duplicate",
                        demonstrations: [
                            uppercaseDemonstration,
                        ]
                    ),
                ],
                includeSeed: false
            ).generate(
                DemonstrationFixtureInference.self,
                examples: examples,
                seed: seed
            )
        } catch AgentInferenceDemonstrationVariantGeneratorError
            .duplicateCandidateIdentifier {
            duplicateRejected = true
        }

        try Expect.equal(
            duplicateRejected,
            true,
            "demonstration generation rejects ambiguous candidate identities"
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
            "demonstration optimization provenance survives codec round trip"
        )

        return [
            .field(
                "generated",
                String(generated.count)
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
                "demonstrations",
                String(
                    result.selectedCandidate
                        .realization
                        .demonstrations
                        .count
                )
            ),
            .field(
                "duplicate_rejected",
                String(duplicateRejected)
            ),
        ]
    }
}
