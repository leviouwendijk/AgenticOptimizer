import AgenticInference
import AgenticOptimizer
import AgenticPrograms
import Foundation
import TestFlows

private struct HeldOutInference: AgentInference {
    typealias Input = String
    typealias Output = String

    static let definition = AgentInferenceDefinition(
        identifier: "fixture.held_out_inference",
        purpose: "Prove held-out examples do not participate in candidate selection."
    )
}

private struct HeldOutProgram: AgentProgram {
    typealias Input = String
    typealias Output = String

    static let descriptor = AgentProgramDescriptor(
        identifier: "fixture.held_out_program",
        title: "Held-Out Program",
        summary: "One-site program used to prove held-out optimization discipline."
    )

    func run(
        _ input: String,
        in context: AgentProgramContext
    ) async throws -> String {
        try await context.infer(
            HeldOutInference.self,
            at: "transform",
            input: input
        )
    }
}

private actor HeldOutExecutionRecorder {
    struct Observation: Sendable {
        let input: String
        let instructions: String
    }

    private var observations: [Observation] = []

    func record(
        input: String,
        instructions: String
    ) {
        observations.append(
            Observation(
                input: input,
                instructions: instructions
            )
        )
    }

    func snapshot() -> [Observation] {
        observations
    }
}

private struct HeldOutExecutor:
    AgentInferenceExecuting,
    Sendable
{
    let recorder: HeldOutExecutionRecorder

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

        case "training_fit":
            outputText =
                inputText == "train"
                ? inputText.uppercased()
                : inputText

        case "evaluation_fit":
            outputText =
                inputText == "evaluation"
                ? inputText.uppercased()
                : inputText

        default:
            throw HeldOutFixtureError.unknownInstructions(
                realization.instructions
            )
        }

        await recorder.record(
            input: inputText,
            instructions: realization.instructions
        )

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

private struct HeldOutInferenceObjective:
    AgentInferenceOptimizationObjective,
    Sendable
{
    let identifier: AgentInferenceOptimizationObjectiveIdentifier =
        "held_out_inference_exact"

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
        let outputData = try JSONEncoder().encode(
            result.output
        )
        let actual = try JSONDecoder().decode(
            String.self,
            from: outputData
        )

        return try AgentInferenceOptimizationScore(
            value: actual == expected
                ? 1.0
                : 0.0
        )
    }
}

private struct HeldOutProgramObjective:
    ProgramOptimization.Objective,
    Sendable
{
    let id: ProgramOptimization.ObjectiveID =
        "held_out_program_exact"

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
            value: actual == expected
                ? 1.0
                : 0.0
        )
    }
}

private enum HeldOutFixtureError:
    Error,
    Sendable
{
    case unknownInstructions(String)
}

extension AgenticOptimizerFlowTesting {
    static func runHeldOutEvaluation()
        async throws
        -> [TestFlowDiagnostic]
    {
        let identity = AgentInferenceRealization(
            strategy: .direct,
            modelSelection: .executor,
            instructions: "identity",
            budget: .singleAttempt
        )
        let trainingFit = AgentInferenceRealization(
            strategy: .direct,
            modelSelection: .executor,
            instructions: "training_fit",
            budget: .singleAttempt
        )
        let evaluationFit = AgentInferenceRealization(
            strategy: .direct,
            modelSelection: .executor,
            instructions: "evaluation_fit",
            budget: .singleAttempt
        )
        let trainingCandidate = AgentInferenceRealizationCandidate(
            identifier: "training_fit",
            realization: trainingFit,
            source: .instruction_variant
        )
        let evaluationCandidate = AgentInferenceRealizationCandidate(
            identifier: "evaluation_fit",
            realization: evaluationFit,
            source: .instruction_variant
        )

        let inferenceDataset =
            try AgentInferenceOptimizationDataset<
                HeldOutInference
            >.parse(
                training: [
                    .init(
                        input: "train",
                        expectedOutput: "TRAIN"
                    ),
                ],
                evaluation: [
                    .init(
                        input: "evaluation",
                        expectedOutput: "EVALUATION"
                    ),
                ]
            )

        var emptyInferenceEvaluationRejected = false

        do {
            _ = try AgentInferenceOptimizationDataset<
                HeldOutInference
            >.parse(
                training: [
                    .init(
                        input: "train",
                        expectedOutput: "TRAIN"
                    ),
                ],
                evaluation: []
            )
        } catch AgentInferenceOptimizationDatasetParsingError
            .noEvaluationExamples {
            emptyInferenceEvaluationRejected = true
        }

        try Expect.equal(
            emptyInferenceEvaluationRejected,
            true,
            "inference optimization datasets require a non-empty held-out evaluation set"
        )

        let inferenceRecorder = HeldOutExecutionRecorder()
        let inferenceSearch = AgentInferenceRealizationSearch(
            executor: HeldOutExecutor(
                recorder: inferenceRecorder
            ),
            objective: HeldOutInferenceObjective()
        )
        let inferenceReport = try await inferenceSearch.optimize(
            HeldOutInference.self,
            dataset: inferenceDataset,
            candidates: [
                trainingCandidate,
                evaluationCandidate,
            ]
        )
        let inferenceObservations =
            await inferenceRecorder.snapshot()

        try Expect.equal(
            inferenceReport.optimization.selectedCandidate.identifier,
            trainingCandidate.identifier,
            "inference candidate selection uses training examples only"
        )
        try Expect.equal(
            inferenceReport.optimization.candidates[0].mean.value,
            1.0,
            "training score records why the training-fit candidate won selection"
        )
        try Expect.equal(
            inferenceReport.evaluation.candidate.identifier,
            trainingCandidate.identifier,
            "held-out evaluation runs the already-selected inference candidate"
        )
        try Expect.equal(
            inferenceReport.evaluation.mean.value,
            0.0,
            "held-out inference evaluation can expose train/evaluation divergence without reselection"
        )
        try Expect.equal(
            inferenceReport.evaluation.trials.count,
            1,
            "held-out inference evaluation records only the selected candidate"
        )
        try Expect.equal(
            inferenceObservations.count,
            3,
            "two training candidate executions are followed by one held-out selected-candidate execution"
        )
        try Expect.equal(
            inferenceObservations.last?.instructions,
            "training_fit",
            "held-out inference execution cannot switch to the candidate that would win on held-out data"
        )
        try Expect.equal(
            inferenceObservations.last?.input,
            "evaluation",
            "held-out inference execution uses the evaluation set only after selection"
        )

        let programDataset =
            try ProgramOptimization.Dataset<HeldOutProgram>.parse(
                training: [
                    .init(
                        input: "train",
                        expectedOutput: "TRAIN"
                    ),
                ],
                evaluation: [
                    .init(
                        input: "evaluation",
                        expectedOutput: "EVALUATION"
                    ),
                ]
            )

        var emptyProgramEvaluationRejected = false

        do {
            _ = try ProgramOptimization
                .Dataset<HeldOutProgram>
                .parse(
                    training: [
                        .init(
                            input: "train",
                            expectedOutput: "TRAIN"
                        ),
                    ],
                    evaluation: []
                )
        } catch ProgramOptimization.DatasetParsingError
            .noEvaluationExamples {
            emptyProgramEvaluationRejected = true
        }

        try Expect.equal(
            emptyProgramEvaluationRejected,
            true,
            "program optimization datasets require a non-empty held-out evaluation set"
        )

        let programTrainingCandidate =
            ProgramOptimization.Candidate<HeldOutProgram>(
                id: "program_training_fit",
                realization: AgentProgramRealization(
                    id: "fixture.program_training_fit",
                    inferences: try AgentProgramInferenceBindings(
                        [
                            AgentInferenceRealizationBinding(
                                site: "transform",
                                inference: HeldOutInference.definition.identifier,
                                realization: trainingFit
                            ),
                        ]
                    )
                )
            )
        let programEvaluationCandidate =
            ProgramOptimization.Candidate<HeldOutProgram>(
                id: "program_evaluation_fit",
                realization: AgentProgramRealization(
                    id: "fixture.program_evaluation_fit",
                    inferences: try AgentProgramInferenceBindings(
                        [
                            AgentInferenceRealizationBinding(
                                site: "transform",
                                inference: HeldOutInference.definition.identifier,
                                realization: evaluationFit
                            ),
                        ]
                    )
                )
            )

        let programRecorder = HeldOutExecutionRecorder()
        let programSearch = ProgramRealizationSearch(
            program: HeldOutProgram(),
            inferenceExecutor: HeldOutExecutor(
                recorder: programRecorder
            ),
            objective: HeldOutProgramObjective()
        )
        let programReport = try await programSearch.optimize(
            dataset: programDataset,
            candidates: [
                programTrainingCandidate,
                programEvaluationCandidate,
            ]
        )
        let programObservations =
            await programRecorder.snapshot()

        try Expect.equal(
            programReport.optimization.selected.id,
            programTrainingCandidate.id,
            "whole-program selection uses training examples only"
        )
        try Expect.equal(
            programReport.evaluation.candidate.id,
            programTrainingCandidate.id,
            "held-out whole-program evaluation preserves the selected program candidate"
        )
        try Expect.equal(
            programReport.evaluation.mean.value,
            0.0,
            "held-out whole-program evaluation reports divergence without changing selection"
        )
        try Expect.equal(
            programObservations.count,
            3,
            "whole-program split executes both candidates on training then only the winner on held-out evaluation"
        )
        try Expect.equal(
            programObservations.last?.instructions,
            "training_fit",
            "whole-program held-out evaluation cannot leak into candidate selection"
        )

        let coordinateRecorder = HeldOutExecutionRecorder()
        let coordinateOptimizer = ProgramCoordinateOptimizer(
            program: HeldOutProgram(),
            inferenceExecutor: HeldOutExecutor(
                recorder: coordinateRecorder
            ),
            objective: HeldOutProgramObjective()
        )
        let coordinateReport = try await coordinateOptimizer.optimize(
            dataset: programDataset,
            seed: AgentProgramRealization(
                id: "fixture.coordinate_held_out_seed",
                inferences: try AgentProgramInferenceBindings(
                    [
                        AgentInferenceRealizationBinding(
                            site: "transform",
                            inference: HeldOutInference.definition.identifier,
                            realization: identity
                        ),
                    ]
                )
            ),
            sites: [
                ProgramOptimization.SiteCandidates(
                    site: "transform",
                    inference: HeldOutInference.definition.identifier,
                    candidates: [
                        trainingCandidate,
                        evaluationCandidate,
                    ]
                ),
            ],
            maximumPasses: 4
        )
        let coordinateObservations =
            await coordinateRecorder.snapshot()

        try Expect.equal(
            coordinateReport.optimization.selected.selections
                .first?.candidate.identifier,
            trainingCandidate.identifier,
            "coordinate optimization chooses its site realization from training evidence only"
        )
        try Expect.equal(
            coordinateReport.optimization.score.value,
            1.0,
            "coordinate optimization retains its training objective score"
        )
        try Expect.equal(
            coordinateReport.evaluation.mean.value,
            0.0,
            "coordinate optimization reports the selected realization's held-out score separately"
        )
        try Expect.equal(
            coordinateReport.evaluation.candidate.id,
            coordinateReport.optimization.selected.id,
            "coordinate held-out evaluation runs exactly the final selected program realization"
        )
        try Expect.equal(
            coordinateObservations.last?.input,
            "evaluation",
            "coordinate held-out data executes only after coordinate search completes"
        )
        try Expect.equal(
            coordinateObservations.last?.instructions,
            "training_fit",
            "coordinate held-out evidence cannot replace the training-selected realization"
        )

        return [
            .field(
                "inference_selected",
                inferenceReport.optimization
                    .selectedCandidate.identifier.rawValue
            ),
            .field(
                "inference_training_score",
                String(
                    inferenceReport.optimization
                        .candidates[0].mean.value
                )
            ),
            .field(
                "inference_held_out_score",
                String(
                    inferenceReport.evaluation.mean.value
                )
            ),
            .field(
                "program_selected",
                programReport.optimization.selected.id.rawValue
            ),
            .field(
                "program_held_out_score",
                String(
                    programReport.evaluation.mean.value
                )
            ),
            .field(
                "coordinate_selected",
                coordinateReport.optimization.selected
                    .selections.first?
                    .candidate.identifier.rawValue
                    ?? "none"
            ),
            .field(
                "coordinate_held_out_score",
                String(
                    coordinateReport.evaluation.mean.value
                )
            ),
        ]
    }
}
