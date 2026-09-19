import Agentic
import AgenticInference
import AgenticOptimizer
import AgenticPrograms
import Foundation
import TestFlows

private struct CoordinatePrepareInference: Inference {
    typealias Input = String
    typealias Output = String

    static let definition = InferenceDefinition(
        identifier: "fixture.coordinate_prepare",
        purpose: "Prepare a value during coordinate optimization."
    )
}

private struct CoordinateFinalizeInference: Inference {
    typealias Input = String
    typealias Output = String

    static let definition = InferenceDefinition(
        identifier: "fixture.coordinate_finalize",
        purpose: "Finalize a value during coordinate optimization."
    )
}

private struct CoordinateFixtureProgram: Program {
    typealias Input = String
    typealias Output = String

    static let definition = ProgramDefinition(
        identifier: "fixture.coordinate_program",
        purpose: "Two-stage program whose sites improve sequentially under whole-program scoring."
    )

    static let prepare = InferenceSite<
        Self,
        CoordinatePrepareInference
    >(
        identifier: .init(
            rawValue: "prepare"
        )
    )

    static let finalize = InferenceSite<
        Self,
        CoordinateFinalizeInference
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

private actor CoordinateExecutionRecorder {
    private var observations: [
        (
            inference: InferenceIdentifier,
            instructions: String
        )
    ] = []

    func record(
        inference: InferenceIdentifier,
        instructions: String
    ) {
        observations.append(
            (
                inference: inference,
                instructions: instructions
            )
        )
    }

    func snapshot() -> [
        (
            inference: InferenceIdentifier,
            instructions: String
        )
    ] {
        observations
    }
}

private struct CoordinateFixtureExecutor:
    InferenceExecuting,
    Sendable
{
    let recorder: CoordinateExecutionRecorder

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
            throw CoordinateFixtureError.unknownInstructions(
                realization.instructions
            )
        }

        await recorder.record(
            inference: inference.definition.identifier,
            instructions: realization.instructions
        )

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

private struct CoordinateProgressObjective:
    ProgramOptimization.Objective,
    Sendable
{
    let id: ProgramOptimization.ObjectiveID =
        "coordinate_progress"

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
        let actualData = try JSONEncoder().encode(
            output
        )
        let actual = try JSONDecoder().decode(
            String.self,
            from: actualData
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

private enum CoordinateFixtureError:
    Error,
    Sendable
{
    case unknownInstructions(String)
}

extension OptimizerFlowTesting {
    static func runProgramCoordinateOptimization()
        async throws
        -> [TestFlowDiagnostic]
    {
        let examples: [
            ProgramOptimization.Example<CoordinateFixtureProgram>
        ] = [
            .init(
                input: "alpha",
                expectedOutput: "ALPHA!"
            ),
            .init(
                input: "beta",
                expectedOutput: "BETA!"
            ),
        ]

        let identity = InferenceRealizationConfiguration(
            strategy: .direct,
            instructions: "identity",
            budget: .singleAttempt
        )
        let uppercase = InferenceRealizationConfiguration(
            strategy: .direct,
            instructions: "uppercase",
            budget: .singleAttempt
        )
        let exclaim = InferenceRealizationConfiguration(
            strategy: .direct,
            instructions: "exclaim",
            budget: .singleAttempt
        )

        let seed = try ProgramRealization<CoordinateFixtureProgram>(
            bindings: [
                .init(
                    CoordinateFixtureProgram.prepare,
                    realization: fixtureInferenceRealization(
                        CoordinatePrepareInference.self,
                        identifier: "prepare.identity",
                        configuration: identity
                    )
                ),
                .init(
                    CoordinateFixtureProgram.finalize,
                    realization: fixtureInferenceRealization(
                        CoordinateFinalizeInference.self,
                        identifier: "finalize.identity",
                        configuration: identity
                    )
                )
            ]
        )

        let sites: [ProgramOptimization.SiteCandidates<CoordinateFixtureProgram>] = [
            .init(
                CoordinateFixtureProgram.prepare,
                candidates: [
                    InferenceRealizationCandidate(
                        identifier: "prepare_identity",
                        realization: identity,
                        source: .seed
                    ),
                    InferenceRealizationCandidate(
                        identifier: "prepare_uppercase",
                        realization: uppercase,
                        source: .instruction_variant,
                        metadata: [
                            "origin": "prepare_coordinate",
                        ]
                    ),
                ]
            ),
            .init(
                CoordinateFixtureProgram.finalize,
                candidates: [
                    InferenceRealizationCandidate(
                        identifier: "finalize_identity",
                        realization: identity,
                        source: .seed
                    ),
                    InferenceRealizationCandidate(
                        identifier: "finalize_exclaim",
                        realization: exclaim,
                        source: .demonstration_variant,
                        metadata: [
                            "origin": "finalize_coordinate",
                        ]
                    ),
                ]
            ),
        ]

        let recorder = CoordinateExecutionRecorder()
        let optimizer = ProgramCoordinateOptimizer(
            program: CoordinateFixtureProgram(),
            inferenceExecutor: CoordinateFixtureExecutor(
                recorder: recorder
            ),
            objective: CoordinateProgressObjective()
        )
        let result = try await optimizer.optimize(
            examples: examples,
            seed: seed,
            sites: sites,
            maximumPasses: 4
        )
        let observations = await recorder.snapshot()

        try Expect.equal(
            result.objective,
            CoordinateProgressObjective().id,
            "coordinate optimization preserves whole-program objective identity"
        )
        try Expect.equal(
            result.score.value,
            1.0,
            "coordinate optimization reaches the jointly improved whole-program realization"
        )
        try Expect.equal(
            result.passesCompleted,
            2,
            "coordinate optimization performs one improving pass and one deterministic convergence pass"
        )
        try Expect.equal(
            result.converged,
            true,
            "coordinate optimization stops when a full pass accepts no improvement"
        )
        try Expect.equal(
            result.decisions.map(\.site.rawValue),
            [
                "prepare",
                "finalize",
                "prepare",
                "finalize",
            ],
            "coordinate optimization visits sites in deterministic declaration order on every pass"
        )
        try Expect.equal(
            result.decisions.map(\.accepted),
            [
                true,
                true,
                false,
                false,
            ],
            "coordinate optimization accepts only strict whole-program improvements and keeps stable ties at the baseline"
        )
        try Expect.equal(
            result.decisions[0].before.value,
            0.0,
            "first coordinate begins from the seed whole-program score"
        )
        try Expect.equal(
            result.decisions[0].after.value,
            0.5,
            "prepare-site uppercase candidate improves the whole-program objective"
        )
        try Expect.equal(
            result.decisions[1].before.value,
            0.5,
            "later coordinates evaluate against earlier accepted improvements from the same pass"
        )
        try Expect.equal(
            result.decisions[1].after.value,
            1.0,
            "finalize-site exclamation candidate compounds the earlier accepted improvement"
        )
        try Expect.equal(
            result.selected.selections.map {
                $0.candidate.identifier.rawValue
            },
            [
                "prepare_uppercase",
                "finalize_exclaim",
            ],
            "final coordinate result preserves exact accepted per-site inference candidate provenance"
        )
        try Expect.equal(
            result.selected.selections[0].candidate.metadata[
                "origin"
            ],
            "prepare_coordinate",
            "coordinate optimization preserves inference candidate metadata provenance"
        )
        try Expect.equal(
            result.trials.count,
            18,
            "coordinate optimization scores the seed once and then evaluates only each site's local alternatives"
        )
        try Expect.equal(
            observations.count,
            36,
            "every seed or coordinate trial executes the actual two-site program"
        )

        let passLimit = try ProgramOptimization
            .CoordinatePassLimit
            .parse(
                2
            )
        let decodedPassLimit = try JSONDecoder().decode(
            ProgramOptimization.CoordinatePassLimit.self,
            from: JSONEncoder().encode(
                passLimit
            )
        )

        try Expect.equal(
            decodedPassLimit,
            passLimit,
            "coordinate pass limits remain Codable through their parsed representation"
        )

        var invalidPassLimitRejected = false

        do {
            _ = try ProgramOptimization.CoordinatePassLimit.parse(
                0
            )
        } catch ProgramOptimization.CoordinatePassLimitError
            .nonPositive {
            invalidPassLimitRejected = true
        }

        try Expect.equal(
            invalidPassLimitRejected,
            true,
            "coordinate pass limits reject non-positive values at parsing"
        )

        let boundedRecorder = CoordinateExecutionRecorder()
        let boundedOptimizer = ProgramCoordinateOptimizer(
            program: CoordinateFixtureProgram(),
            inferenceExecutor: CoordinateFixtureExecutor(
                recorder: boundedRecorder
            ),
            objective: CoordinateProgressObjective()
        )
        let bounded = try await boundedOptimizer.optimize(
            examples: examples,
            seed: seed,
            sites: sites,
            maximumPasses: 1
        )

        try Expect.equal(
            bounded.passesCompleted,
            1,
            "coordinate optimization respects its parsed pass bound"
        )
        try Expect.equal(
            bounded.converged,
            false,
            "a pass that accepted improvements is not falsely reported as converged when the pass budget ends"
        )

        return [
            .field(
                "passes",
                String(result.passesCompleted)
            ),
            .field(
                "decisions",
                String(result.decisions.count)
            ),
            .field(
                "accepted",
                String(
                    result.decisions.filter(\.accepted).count
                )
            ),
            .field(
                "trials",
                String(result.trials.count)
            ),
            .field(
                "score",
                String(result.score.value)
            ),
            .field(
                "converged",
                String(result.converged)
            ),
            .field(
                "bounded_passes",
                String(bounded.passesCompleted)
            ),
        ]
    }
}