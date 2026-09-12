import AgenticInference
import AgenticOptimizer
import AgenticPrograms
import Foundation
import Primitives
import TestFlows

private struct CompilerPrepareInference: AgentInference {
    typealias Input = String
    typealias Output = String

    static let definition = AgentInferenceDefinition(
        identifier: "fixture.compiler_prepare",
        purpose: "Prepare a value for Program optimization compilation."
    )
}

private struct CompilerFinalizeInference: AgentInference {
    typealias Input = String
    typealias Output = String

    static let definition = AgentInferenceDefinition(
        identifier: "fixture.compiler_finalize",
        purpose: "Finalize a value for Program optimization compilation."
    )
}

private struct CompilerFixtureProgram: AgentProgram {
    typealias Input = String
    typealias Output = String

    static let descriptor = AgentProgramDescriptor(
        identifier: "fixture.optimization_compiler",
        title: "Optimization Compiler Fixture",
        summary: "Two-site Program compiled from typed per-site candidate generators."
    )

    func run(
        _ input: String,
        in context: AgentProgramContext
    ) async throws -> String {
        let prepared = try await context.infer(
            CompilerPrepareInference.self,
            at: "prepare",
            input: input
        )

        return try await context.infer(
            CompilerFinalizeInference.self,
            at: "finalize",
            input: prepared
        )
    }
}

private struct CompilerFixtureExecutor:
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

        case "exclaim":
            outputText = inputText + "!"

        default:
            throw CompilerFixtureError.unknownInstructions(
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
                budget: realization.budget
            )
        )
    }
}

private struct CompilerProgramObjective:
    ProgramOptimization.Objective,
    Sendable
{
    let id: ProgramOptimization.ObjectiveID =
        "compiler_progress"

    func score<Program: AgentProgram>(
        _ program: Program.Type,
        example: ProgramOptimization.Example<Program>,
        output: Program.Output
    ) async throws -> AgentInferenceOptimizationScore {
        let expectedData = try JSONEncoder().encode(
            example.expectedOutput
        )
        let expected = try JSONDecoder().decode(
            String.self,
            from: expectedData
        )
        let outputData = try JSONEncoder().encode(
            output
        )
        let actual = try JSONDecoder().decode(
            String.self,
            from: outputData
        )
        let expectedBase = String(
            expected.dropLast()
        )

        let value: Double

        if actual == expected {
            value = 1.0
        } else if actual == expectedBase
            || actual.hasSuffix("!")
        {
            value = 0.5
        } else {
            value = 0.0
        }

        return try AgentInferenceOptimizationScore(
            value: value,
            metadata: [
                "expected": expected,
                "actual": actual,
            ]
        )
    }
}

private enum CompilerFixtureError:
    Error,
    Sendable
{
    case unknownInstructions(String)
}

extension AgenticOptimizerFlowTesting {
    static func runProgramOptimizationCompiler()
        async throws
        -> [TestFlowDiagnostic]
    {
        let identity = AgentInferenceRealization(
            strategy: .direct,
            modelSelection: .executor,
            instructions: "identity",
            budget: .singleAttempt
        )

        let seed = AgentProgramRealization<CompilerFixtureProgram>(
            id: "fixture.compiler_seed",
            inferences: try AgentProgramInferenceBindings(
                [
                    AgentInferenceRealizationBinding(
                        site: "prepare",
                        inference:
                            CompilerPrepareInference.definition.identifier,
                        realization: identity
                    ),
                    AgentInferenceRealizationBinding(
                        site: "finalize",
                        inference:
                            CompilerFinalizeInference.definition.identifier,
                        realization: identity
                    ),
                ]
            ),
            metadata: [
                "seed_marker": "preserved",
            ]
        )

        let prepareGenerator =
            try AgentInferenceInstructionVariantGenerator.parse(
                variants: [
                    AgentInferenceInstructionVariant(
                        identifier:
                            AgentInferenceRealizationCandidateIdentifier(
                                rawValue: "prepare_uppercase"
                            ),
                        instructions: "uppercase",
                        metadata: [
                            "compiler.site": "prepare",
                        ]
                    ),
                ],
                includeSeed: true,
                seedIdentifier:
                    AgentInferenceRealizationCandidateIdentifier(
                        rawValue: "prepare_identity"
                    )
            )
        let finalizeGenerator =
            try AgentInferenceInstructionVariantGenerator.parse(
                variants: [
                    AgentInferenceInstructionVariant(
                        identifier:
                            AgentInferenceRealizationCandidateIdentifier(
                                rawValue: "finalize_exclaim"
                            ),
                        instructions: "exclaim",
                        metadata: [
                            "compiler.site": "finalize",
                        ]
                    ),
                ],
                includeSeed: true,
                seedIdentifier:
                    AgentInferenceRealizationCandidateIdentifier(
                        rawValue: "finalize_identity"
                    )
            )

        let prepareSite =
            try ProgramOptimization
                .CompilationSite<CompilerFixtureProgram>
                .parse(
                    CompilerPrepareInference.self,
                    at: "prepare",
                    examples: [
                        .init(
                            input: "alpha",
                            expectedOutput: "ALPHA"
                        ),
                        .init(
                            input: "beta",
                            expectedOutput: "BETA"
                        ),
                    ],
                    generator: prepareGenerator
                )
        let finalizeSite =
            try ProgramOptimization
                .CompilationSite<CompilerFixtureProgram>
                .parse(
                    CompilerFinalizeInference.self,
                    at: "finalize",
                    examples: [
                        .init(
                            input: "ALPHA",
                            expectedOutput: "ALPHA!"
                        ),
                        .init(
                            input: "BETA",
                            expectedOutput: "BETA!"
                        ),
                    ],
                    generator: finalizeGenerator
                )

        let dataset =
            try ProgramOptimization
                .Dataset<CompilerFixtureProgram>
                .parse(
                    training: [
                        .init(
                            input: "alpha",
                            expectedOutput: "ALPHA!"
                        ),
                        .init(
                            input: "beta",
                            expectedOutput: "BETA!"
                        ),
                    ],
                    evaluation: [
                        .init(
                            input: "gamma",
                            expectedOutput: "GAMMA!"
                        ),
                    ]
                )

        let compiler = ProgramOptimizationCompiler(
            program: CompilerFixtureProgram(),
            inferenceExecutor: CompilerFixtureExecutor(),
            objective: CompilerProgramObjective()
        )
        let report = try await compiler.compile(
            dataset: dataset,
            seed: seed,
            sites: [
                prepareSite,
                finalizeSite,
            ],
            maximumPasses: 4
        )

        try Expect.equal(
            report.generatedSites.map(\.site.rawValue),
            [
                "prepare",
                "finalize",
            ],
            "optimization compilation preserves declared inference-site order"
        )
        try Expect.equal(
            report.generatedSites.map {
                $0.candidates.count
            },
            [
                2,
                2,
            ],
            "optimization compilation generates each site's candidate space before whole-program search"
        )
        try Expect.equal(
            report.selectedRealization
                .realization(
                    at: "prepare"
                )?
                .instructions,
            "uppercase",
            "compiler selects the improved prepare-site realization"
        )
        try Expect.equal(
            report.selectedRealization
                .realization(
                    at: "finalize"
                )?
                .instructions,
            "exclaim",
            "compiler selects the improved finalize-site realization"
        )
        try Expect.equal(
            report.selectedRealization.metadata[
                "seed_marker"
            ],
            "preserved",
            "optimization compilation preserves seed Program realization metadata"
        )
        try Expect.equal(
            report.optimization.optimization.score.value,
            1.0,
            "compiler optimizes against the actual whole Program training objective"
        )
        try Expect.equal(
            report.optimization.evaluation.mean.value,
            1.0,
            "compiler evaluates the already-selected Program realization on held-out examples"
        )
        try Expect.equal(
            report.optimization.optimization.selected
                .selections.map {
                    $0.candidate.identifier.rawValue
                },
            [
                "prepare_uppercase",
                "finalize_exclaim",
            ],
            "compiler preserves exact accepted per-site candidate provenance"
        )

        var duplicateSiteRejected = false

        do {
            _ = try ProgramOptimization
                .CompilationPlan<CompilerFixtureProgram>
                .parse(
                    seed: seed,
                    sites: [
                        prepareSite,
                        prepareSite,
                    ]
                )
        } catch ProgramOptimization.CompilationPlanParsingError
            .duplicateSite {
            duplicateSiteRejected = true
        }

        try Expect.equal(
            duplicateSiteRejected,
            true,
            "compilation plans reject duplicate inference sites before candidate generation"
        )

        var missingSeedBindingRejected = false

        let missingBindingSeed =
            AgentProgramRealization<CompilerFixtureProgram>(
                id: "fixture.compiler_missing_binding",
                inferences: try AgentProgramInferenceBindings(
                    [
                        AgentInferenceRealizationBinding(
                            site: "prepare",
                            inference:
                                CompilerPrepareInference
                                    .definition.identifier,
                            realization: identity
                        ),
                    ]
                )
            )

        do {
            _ = try ProgramOptimization
                .CompilationPlan<CompilerFixtureProgram>
                .parse(
                    seed: missingBindingSeed,
                    sites: [
                        prepareSite,
                        finalizeSite,
                    ]
                )
        } catch ProgramOptimization.CompilationPlanParsingError
            .seedBindingUnavailable {
            missingSeedBindingRejected = true
        }

        try Expect.equal(
            missingSeedBindingRejected,
            true,
            "compilation plans prove every optimizable site is present in the seed realization"
        )

        return [
            .field(
                "generated_sites",
                String(report.generatedSites.count)
            ),
            .field(
                "selected_prepare",
                report.selectedRealization
                    .realization(
                        at: "prepare"
                    )?
                    .instructions
                    ?? "none"
            ),
            .field(
                "selected_finalize",
                report.selectedRealization
                    .realization(
                        at: "finalize"
                    )?
                    .instructions
                    ?? "none"
            ),
            .field(
                "training_score",
                String(
                    report.optimization.optimization.score.value
                )
            ),
            .field(
                "held_out_score",
                String(
                    report.optimization.evaluation.mean.value
                )
            ),
            .field(
                "duplicate_site_rejected",
                String(duplicateSiteRejected)
            ),
            .field(
                "missing_binding_rejected",
                String(missingSeedBindingRejected)
            ),
        ]
    }
}
