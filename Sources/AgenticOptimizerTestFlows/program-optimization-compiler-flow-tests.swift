import Agentic
import AgenticInference
import AgenticOptimizer
import AgenticPrograms
import Foundation
import Primitives
import TestFlows

private struct CompilerPrepareInference: Inference {
    typealias Input = String
    typealias Output = String

    static let definition = InferenceDefinition(
        identifier: "fixture.compiler_prepare",
        purpose: "Prepare a value for Program optimization compilation."
    )
}

private struct CompilerFinalizeInference: Inference {
    typealias Input = String
    typealias Output = String

    static let definition = InferenceDefinition(
        identifier: "fixture.compiler_finalize",
        purpose: "Finalize a value for Program optimization compilation."
    )
}

private struct CompilerFixtureProgram: Program {
    typealias Input = String
    typealias Output = String

    static let definition = ProgramDefinition(
        identifier: "fixture.optimization_compiler",
        purpose: "Two-site Program compiled from typed per-site candidate generators."
    )

    static let prepare = InferenceSite<
        Self,
        CompilerPrepareInference
    >(
        identifier: .init(
            rawValue: "prepare"
        )
    )

    static let finalize = InferenceSite<
        Self,
        CompilerFinalizeInference
    >(
        identifier: .init(
            rawValue: "finalize"
        )
    )

    func run(
        _ input: String,
        in context: ProgramContext
    ) async throws -> String {
        let prepared = try await context.infer(
            Self.prepare,
            input: input
        )

        return try await context.infer(
            Self.finalize,
            input: prepared
        )
    }
}

private struct CompilerFixtureExecutor:
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
        return InferenceInvocationResult(
            output: outputData,
            record: InferenceExecutionRecord(
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

    func score<ProgramType: Program>(
        _ program: ProgramType.Type,
        example: ProgramOptimization.Example<ProgramType>,
        output: ProgramType.Output
    ) async throws -> InferenceOptimizationScore {
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

        return try InferenceOptimizationScore(
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

extension OptimizerFlowTesting {
    static func runProgramOptimizationCompiler()
        async throws
        -> [TestFlowDiagnostic]
    {
        let identity = InferenceRealizationConfiguration(
            strategy: .direct,
            instructions: "identity",
            budget: .singleAttempt
        )

        let seed = try ProgramRealization<CompilerFixtureProgram>(
            bindings: [
                .init(
                    CompilerFixtureProgram.prepare,
                    realization: fixtureInferenceRealization(
                        CompilerPrepareInference.self,
                        identifier: "prepare.identity",
                        configuration: identity
                    )
                ),
                .init(
                    CompilerFixtureProgram.finalize,
                    realization: fixtureInferenceRealization(
                        CompilerFinalizeInference.self,
                        identifier: "finalize.identity",
                        configuration: identity
                    )
                )
            ]
        )

        let prepareGenerator =
            try InferenceInstructionVariantGenerator.parse(
                variants: [
                    InferenceInstructionVariant(
                        identifier:
                            InferenceRealizationCandidateIdentifier(
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
                    InferenceRealizationCandidateIdentifier(
                        rawValue: "prepare_identity"
                    )
            )
        let finalizeGenerator =
            try InferenceInstructionVariantGenerator.parse(
                variants: [
                    InferenceInstructionVariant(
                        identifier:
                            InferenceRealizationCandidateIdentifier(
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
                    InferenceRealizationCandidateIdentifier(
                        rawValue: "finalize_identity"
                    )
            )

        let prepareSite =
            try ProgramOptimization
                .CompilationSite<CompilerFixtureProgram>
                .parse(
                    CompilerFixtureProgram.prepare,
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
                    CompilerFixtureProgram.finalize,
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
                .binding(
                    for: CompilerFixtureProgram.prepare
                )?
                .configuration
                .instructions,
            "uppercase",
            "compiler selects the improved prepare-site realization"
        )
        try Expect.equal(
            report.selectedRealization
                .binding(
                    for: CompilerFixtureProgram.finalize
                )?
                .configuration
                .instructions,
            "exclaim",
            "compiler selects the improved finalize-site realization"
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
            try ProgramRealization<CompilerFixtureProgram>(
                bindings: [
                    .init(
                        CompilerFixtureProgram.prepare,
                        realization: fixtureInferenceRealization(
                            CompilerPrepareInference.self,
                            identifier: "prepare.identity",
                            configuration: identity
                        )
                    )
                ]
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
                    .binding(
                        for: CompilerFixtureProgram.prepare
                    )?
                    .configuration
                    .instructions
                    ?? "none"
            ),
            .field(
                "selected_finalize",
                report.selectedRealization
                    .binding(
                        for: CompilerFixtureProgram.finalize
                    )?
                    .configuration
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