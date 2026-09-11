import AgenticInference
import AgenticOptimizer
import Foundation
import TestFlows

private struct GeneratedCandidateFixtureInference: AgentInference {
    typealias Input = String
    typealias Output = String

    static let definition = AgentInferenceDefinition(
        identifier: "fixture.generated_candidate_search",
        purpose: "Prove generated realization candidates compose with optimization search."
    )
}

private struct GeneratedCandidateFixtureExecutor:
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

        case "constant":
            outputText = "ALPHA"

        case "uppercase":
            outputText = inputText.uppercased()

        default:
            throw GeneratedCandidateFixtureError
                .unknownInstructions(
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

private struct GeneratedCandidateExactObjective:
    AgentInferenceOptimizationObjective,
    Sendable
{
    let identifier: AgentInferenceOptimizationObjectiveIdentifier =
        "generated_exact_output"

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

        return try AgentInferenceOptimizationScore(
            value: expected == actual ? 1.0 : 0.0
        )
    }
}

private enum GeneratedCandidateFixtureError:
    Error,
    Sendable
{
    case unknownInstructions(String)
}

extension AgenticOptimizerFlowTesting {
    static func runInstructionCandidateGeneration()
        async throws
        -> [TestFlowDiagnostic]
    {
        let examples: [
            AgentInferenceOptimizationExample<GeneratedCandidateFixtureInference>
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
            instructions: "identity",
            budget: .singleAttempt,
            metadata: [
                "seed_marker": "preserved",
            ]
        )
        let generator = try AgentInferenceInstructionVariantGenerator.parse(
            variants: [
                .init(
                    identifier: "constant",
                    instructions: "constant",
                    metadata: [
                        "variant": "constant",
                    ]
                ),
                .init(
                    identifier: "uppercase",
                    instructions: "uppercase",
                    metadata: [
                        "variant": "uppercase",
                    ]
                ),
            ],
            includeSeed: true,
            seedIdentifier: "baseline"
        )

        let generated = try await generator.generate(
            GeneratedCandidateFixtureInference.self,
            examples: examples,
            seed: seed
        )

        try Expect.equal(
            generated.count,
            3,
            "instruction generator emits seed and configured variants"
        )
        try Expect.equal(
            generated[0].identifier,
            AgentInferenceRealizationCandidateIdentifier(
                "baseline"
            ),
            "instruction generator assigns explicit baseline identity"
        )
        try Expect.equal(
            generated[0].source,
            .seed,
            "baseline candidate preserves typed seed provenance"
        )
        try Expect.equal(
            generated[1].source,
            .instruction_variant,
            "generated candidate records typed instruction-variant provenance"
        )
        try Expect.equal(
            generated[2].realization.instructions,
            "uppercase",
            "instruction generator replaces only candidate instructions"
        )
        try Expect.equal(
            generated[2].realization.strategy,
            seed.strategy,
            "instruction generation preserves seed execution strategy"
        )
        try Expect.equal(
            generated[2].realization.modelSelection,
            seed.modelSelection,
            "instruction generation preserves seed model selection"
        )
        try Expect.equal(
            generated[2].realization.budget,
            seed.budget,
            "instruction generation preserves seed inference budget"
        )
        try Expect.equal(
            generated[2].realization.metadata[
                "seed_marker"
            ],
            "preserved",
            "instruction generation preserves seed realization metadata"
        )
        try Expect.equal(
            generated[2].metadata[
                "variant"
            ],
            "uppercase",
            "candidate-level metadata remains separate from realization metadata"
        )

        let search = AgentInferenceRealizationSearch(
            executor: GeneratedCandidateFixtureExecutor(),
            objective: GeneratedCandidateExactObjective()
        )
        let result = try await search.optimize(
            GeneratedCandidateFixtureInference.self,
            examples: examples,
            seed: seed,
            generator: generator
        )

        try Expect.equal(
            result.candidates.count,
            3,
            "search evaluates every generated candidate"
        )
        try Expect.equal(
            result.trials.count,
            6,
            "generated candidate search evaluates every candidate against every example"
        )
        try Expect.equal(
            result.selectedCandidate.identifier,
            AgentInferenceRealizationCandidateIdentifier(
                "uppercase"
            ),
            "generated candidate search selects the best instruction variant"
        )
        try Expect.equal(
            result.selectedCandidate.source,
            .instruction_variant,
            "selected candidate retains generation provenance"
        )
        try Expect.equal(
            result.selectedCandidate.realization.instructions,
            "uppercase",
            "optimization result contains directly reusable selected realization"
        )

        var duplicateRejected = false

        do {
            _ = try AgentInferenceInstructionVariantGenerator.parse(
                variants: [
                    .init(
                        identifier: "duplicate",
                        instructions: "constant"
                    ),
                    .init(
                        identifier: "duplicate",
                        instructions: "uppercase"
                    ),
                ],
                includeSeed: false
            )
        } catch AgentInferenceInstructionVariantGeneratorError
            .duplicateCandidateIdentifier {
            duplicateRejected = true
        }

        try Expect.equal(
            duplicateRejected,
            true,
            "instruction generation rejects ambiguous candidate identities"
        )

        var emptyInstructionsRejected = false

        do {
            _ = try AgentInferenceInstructionVariantGenerator.parse(
                variants: [
                    .init(
                        identifier: "empty",
                        instructions: "   "
                    ),
                ],
                includeSeed: false
            )
        } catch AgentInferenceInstructionVariantGeneratorError
            .emptyInstructions {
            emptyInstructionsRejected = true
        }

        try Expect.equal(
            emptyInstructionsRejected,
            true,
            "instruction candidate parsing rejects empty instructions before generation"
        )

        var noCandidatesRejected = false

        do {
            _ = try AgentInferenceInstructionVariantGenerator.parse(
                variants: [],
                includeSeed: false
            )
        } catch AgentInferenceInstructionVariantGeneratorError
            .noCandidates {
            noCandidatesRejected = true
        }

        try Expect.equal(
            noCandidatesRejected,
            true,
            "instruction candidate parsing guarantees a non-empty generated candidate set"
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
            "generated-candidate optimization provenance survives codec round trip"
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
                "duplicate_rejected",
                String(duplicateRejected)
            ),
            .field(
                "empty_rejected",
                String(emptyInstructionsRejected)
            ),
        ]
    }
}
