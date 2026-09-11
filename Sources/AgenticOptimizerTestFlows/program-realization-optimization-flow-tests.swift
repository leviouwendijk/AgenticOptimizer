import AgenticInference
import AgenticOptimizer
import AgenticPrograms
import Foundation
import TestFlows

private struct PrepareProgramInference: AgentInference {
    typealias Input = String
    typealias Output = String

    static let definition = AgentInferenceDefinition(
        identifier: "fixture.program_prepare",
        purpose: "Prepare a value for the next program stage."
    )
}

private struct FinalizeProgramInference: AgentInference {
    typealias Input = String
    typealias Output = String

    static let definition = AgentInferenceDefinition(
        identifier: "fixture.program_finalize",
        purpose: "Finalize a prepared program value."
    )
}

private struct OptimizationFixtureProgram: AgentProgram {
    typealias Input = String
    typealias Output = String

    static let descriptor = AgentProgramDescriptor(
        identifier: "fixture.program_optimization",
        title: "Program Optimization Fixture",
        summary: "Two-stage inference program used to prove whole-program realization optimization."
    )

    func run(
        _ input: String,
        in context: AgentProgramContext
    ) async throws -> String {
        let prepared = try await context.infer(
            PrepareProgramInference.self,
            at: "prepare",
            input: input
        )

        return try await context.infer(
            FinalizeProgramInference.self,
            at: "finalize",
            input: prepared
        )
    }
}

private struct ProgramExecutionObservation: Sendable {
    var inference: AgentInferenceIdentifier
    var instructions: String
}

private actor ProgramExecutionRecorder {
    private var observations: [ProgramExecutionObservation] = []

    func append(
        _ observation: ProgramExecutionObservation
    ) {
        observations.append(
            observation
        )
    }

    func snapshot() -> [ProgramExecutionObservation] {
        observations
    }
}

private struct ProgramOptimizationFixtureExecutor:
    AgentInferenceExecuting,
    Sendable
{
    let recorder: ProgramExecutionRecorder

    func execute<Inference: AgentInference>(
        _ inference: Inference.Type,
        input: Inference.Input,
        realization: AgentInferenceRealization
    ) async throws -> AgentInferenceExecutionResult<Inference.Output> {
        await recorder.append(
            ProgramExecutionObservation(
                inference: inference.definition.identifier,
                instructions: realization.instructions
            )
        )

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

        default:
            throw ProgramOptimizationFixtureError
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

private struct ProgramExactObjective:
    ProgramOptimization.Objective,
    Sendable
{
    let id: ProgramOptimization.ObjectiveID =
        "exact_program_output"

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

        return try AgentInferenceOptimizationScore(
            value: expected == actual ? 1.0 : 0.0,
            metadata: [
                "expected": expected,
                "actual": actual,
            ]
        )
    }
}

private enum ProgramOptimizationFixtureError:
    Error,
    Sendable
{
    case unknownInstructions(String)
}

extension AgenticOptimizerFlowTesting {
    static func runProgramRealizationOptimization()
        async throws
        -> [TestFlowDiagnostic]
    {
        let examples: [
            ProgramOptimization.Example<OptimizationFixtureProgram>
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

        let identity = AgentInferenceRealization(
            strategy: .direct,
            modelSelection: .executor,
            instructions: "identity",
            budget: .singleAttempt
        )
        let uppercase = AgentInferenceRealization(
            strategy: .direct,
            modelSelection: .executor,
            instructions: "uppercase",
            budget: .singleAttempt
        )

        let candidates: [
            ProgramOptimization.Candidate<OptimizationFixtureProgram>
        ] = [
            .init(
                id: "baseline",
                realization: AgentProgramRealization(
                    id: "fixture.program.baseline",
                    inferences: try AgentProgramInferenceBindings(
                        [
                            AgentInferenceRealizationBinding(
                                site: "prepare",
                                inference: PrepareProgramInference.definition.identifier,
                                realization: identity
                            ),
                            AgentInferenceRealizationBinding(
                                site: "finalize",
                                inference: FinalizeProgramInference.definition.identifier,
                                realization: identity
                            ),
                        ]
                    )
                )
            ),
            .init(
                id: "prepare_uppercase",
                realization: AgentProgramRealization(
                    id: "fixture.program.prepare_uppercase",
                    inferences: try AgentProgramInferenceBindings(
                        [
                            AgentInferenceRealizationBinding(
                                site: "prepare",
                                inference: PrepareProgramInference.definition.identifier,
                                realization: uppercase
                            ),
                            AgentInferenceRealizationBinding(
                                site: "finalize",
                                inference: FinalizeProgramInference.definition.identifier,
                                realization: identity
                            ),
                        ]
                    )
                )
            ),
            .init(
                id: "finalize_uppercase",
                realization: AgentProgramRealization(
                    id: "fixture.program.finalize_uppercase",
                    inferences: try AgentProgramInferenceBindings(
                        [
                            AgentInferenceRealizationBinding(
                                site: "prepare",
                                inference: PrepareProgramInference.definition.identifier,
                                realization: identity
                            ),
                            AgentInferenceRealizationBinding(
                                site: "finalize",
                                inference: FinalizeProgramInference.definition.identifier,
                                realization: uppercase
                            ),
                        ]
                    )
                )
            ),
        ]

        let recorder = ProgramExecutionRecorder()
        let search = ProgramRealizationSearch(
            program: OptimizationFixtureProgram(),
            inferenceExecutor: ProgramOptimizationFixtureExecutor(
                recorder: recorder
            ),
            objective: ProgramExactObjective()
        )
        let result = try await search.optimize(
            examples: examples,
            candidates: candidates
        )
        let observations = await recorder.snapshot()

        try Expect.equal(
            result.objective,
            ProgramExactObjective().id,
            "program optimization preserves objective identity"
        )
        try Expect.equal(
            result.candidates.count,
            3,
            "program optimization evaluates every supplied whole-program realization"
        )
        try Expect.equal(
            result.trials.count,
            6,
            "program optimization evaluates every realization against every example"
        )
        try Expect.equal(
            result.candidates[0].meanScore,
            0.0,
            "all-identity program realization fails the uppercase objective"
        )
        try Expect.equal(
            result.candidates[1].meanScore,
            1.0,
            "changing the prepare site can optimize the final program output"
        )
        try Expect.equal(
            result.candidates[2].meanScore,
            1.0,
            "changing the finalize site can independently optimize the final program output"
        )
        try Expect.equal(
            result.selected.id,
            ProgramOptimization.CandidateID(
                "prepare_uppercase"
            ),
            "program optimization uses stable first-candidate tie breaking"
        )
        try Expect.equal(
            result.candidates[1].trialIndexes,
            [
                2,
                3,
            ],
            "program candidate result preserves global trial provenance"
        )
        try Expect.equal(
            observations.count,
            12,
            "each candidate example executes both semantic inference sites"
        )

        let prepareUppercaseCount = observations.filter {
            $0.inference == PrepareProgramInference.definition.identifier
                && $0.instructions == "uppercase"
        }.count
        let finalizeUppercaseCount = observations.filter {
            $0.inference == FinalizeProgramInference.definition.identifier
                && $0.instructions == "uppercase"
        }.count

        try Expect.equal(
            prepareUppercaseCount,
            2,
            "program evaluation resolves the candidate realization bound to the prepare site"
        )
        try Expect.equal(
            finalizeUppercaseCount,
            2,
            "program evaluation resolves the candidate realization bound to the finalize site"
        )

        var emptyCandidatesRejected = false

        do {
            _ = try await search.optimize(
                examples: examples,
                candidates: []
            )
        } catch ProgramOptimization.ProblemParsingError.noCandidates {
            emptyCandidatesRejected = true
        }

        try Expect.equal(
            emptyCandidatesRejected,
            true,
            "program optimization rejects an empty realization search space"
        )

        var emptyExamplesRejected = false

        do {
            _ = try await search.optimize(
                examples: [],
                candidates: candidates
            )
        } catch ProgramOptimization.ProblemParsingError.noExamples {
            emptyExamplesRejected = true
        }

        try Expect.equal(
            emptyExamplesRejected,
            true,
            "program optimization rejects evaluation without examples"
        )

        return [
            .field(
                "candidates",
                String(result.candidates.count)
            ),
            .field(
                "trials",
                String(result.trials.count)
            ),
            .field(
                "site_executions",
                String(observations.count)
            ),
            .field(
                "selected",
                result.selected.id.rawValue
            ),
            .field(
                "prepare_uppercase",
                String(prepareUppercaseCount)
            ),
            .field(
                "finalize_uppercase",
                String(finalizeUppercaseCount)
            ),
            .field(
                "stable_tie_break",
                "true"
            ),
        ]
    }
}
