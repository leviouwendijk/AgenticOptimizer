import Agentic
import AgenticInference
import AgenticOptimizer
import Foundation
import Primitives
import TestFlows

private struct DemonstrationFixtureInference: Inference {
    typealias Input = String
    typealias Output = String

    static let definition = InferenceDefinition(
        identifier: "fixture.demonstration_search",
        purpose: "Prove demonstration sets can be optimized independently from other realization fields."
    )
}

private struct DemonstrationFixtureExecutor:
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
        return InferenceInvocationResult(
            output: outputData,
            record: InferenceExecutionRecord(
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
    InferenceOptimizationObjective,
    Sendable
{
    let identifier: InferenceOptimizationObjectiveIdentifier =
        "demonstration_exact_output"

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

private enum DemonstrationFixtureError:
    Error,
    Sendable
{
    case unknownBehavior(String)
}

extension OptimizerFlowTesting {
    static func runDemonstrationOptimization()
        async throws
        -> [TestFlowDiagnostic]
    {
        let examples: [
            InferenceOptimizationExample<DemonstrationFixtureInference>
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

        let seed = InferenceRealizationConfiguration(
            strategy: .direct,
            instructions: "Use the supplied demonstrations to perform the transformation.",
            budget: .singleAttempt,
            demonstrations: [],
            metadata: [
                "seed_marker": "preserved",
            ]
        )

        let constantDemonstration = InferenceDemonstration(
            input: .string("alpha"),
            output: .string("ALPHA"),
            metadata: [
                "fixture.behavior": "constant",
            ]
        )
        let uppercaseDemonstration = InferenceDemonstration(
            input: .string("example"),
            output: .string("EXAMPLE"),
            metadata: [
                "fixture.behavior": "uppercase",
            ]
        )

        let generator = try InferenceDemonstrationVariantGenerator.parse(
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

        let search = InferenceRealizationSearch(
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
            InferenceRealizationCandidateIdentifier(
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
            _ = try InferenceDemonstrationVariantGenerator.parse(
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
            )
        } catch InferenceDemonstrationVariantGeneratorError
            .duplicateCandidateIdentifier {
            duplicateRejected = true
        }

        try Expect.equal(
            duplicateRejected,
            true,
            "demonstration candidate parsing rejects ambiguous candidate identities"
        )

        var noCandidatesRejected = false

        do {
            _ = try InferenceDemonstrationVariantGenerator.parse(
                variants: [],
                includeSeed: false
            )
        } catch InferenceDemonstrationVariantGeneratorError
            .noCandidates {
            noCandidatesRejected = true
        }

        try Expect.equal(
            noCandidatesRejected,
            true,
            "demonstration candidate parsing guarantees a non-empty generated candidate set"
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