import AgenticInference
import AgenticOptimizer
import AgenticPrograms
import Foundation
import TestFlows

private struct MultiObjectiveInference: AgentInference {
    typealias Input = String
    typealias Output = String

    static let definition = AgentInferenceDefinition(
        identifier: "fixture.multi_objective_inference",
        purpose: "Exercise quality and resource tradeoffs."
    )
}

private struct MultiObjectiveProgram: AgentProgram {
    typealias Input = String
    typealias Output = String

    static let descriptor = AgentProgramDescriptor(
        identifier: "fixture.multi_objective_program",
        title: "Multi Objective Program",
        summary: "One-site program for multi-objective optimization."
    )

    func run(
        _ input: String,
        in context: AgentProgramContext
    ) async throws -> String {
        try await context.infer(
            MultiObjectiveInference.self,
            at: "transform",
            input: input
        )
    }
}

private struct MultiObjectiveFixtureExecutor:
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
        let resourceClass: String

        switch realization.instructions {
        case "quality":
            outputText = inputText.uppercased()
            resourceClass = "expensive"

        case "balanced":
            outputText =
                inputText == "alpha"
                ? inputText.uppercased()
                : inputText
            resourceClass = "balanced"

        case "cheap":
            outputText = inputText
            resourceClass = "cheap"

        default:
            throw MultiObjectiveFixtureError
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
                metadata: [
                    "resource_class": resourceClass,
                ]
            )
        )
    }
}

private struct MultiObjectiveFixtureResourceEstimator:
    AgentOptimizationResourceEstimating,
    Sendable
{
    func estimate(
        executions: [AgentInferenceExecutionRecord],
        measuredDurationSeconds: Double
    ) throws -> AgentOptimizationResourceMetrics {
        let resourceClass =
            executions.first?.metadata[
                "resource_class"
            ]
            ?? "cheap"

        switch resourceClass {
        case "expensive":
            return try AgentOptimizationResourceMetrics.parse(
                totalTokens: 100,
                estimatedUsd: 10,
                latencySeconds: 10
            )

        case "balanced":
            return try AgentOptimizationResourceMetrics.parse(
                totalTokens: 20,
                estimatedUsd: 2,
                latencySeconds: 2
            )

        default:
            return try AgentOptimizationResourceMetrics.parse(
                totalTokens: 10,
                estimatedUsd: 1,
                latencySeconds: 1
            )
        }
    }
}

private struct MultiObjectiveInferenceObjective:
    AgentInferenceOptimizationObjective,
    Sendable
{
    let identifier: AgentInferenceOptimizationObjectiveIdentifier =
        "multi_objective_quality"

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
            value:
                actual == expected
                ? 1
                : 0
        )
    }
}

private struct MultiObjectiveProgramObjective:
    ProgramOptimization.Objective,
    Sendable
{
    let id: ProgramOptimization.ObjectiveID =
        "multi_objective_program_quality"

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
            value:
                actual == expected
                ? 1
                : 0
        )
    }
}

private enum MultiObjectiveFixtureError:
    Error,
    Sendable
{
    case unknownInstructions(String)
}

extension AgenticOptimizerFlowTesting {
    static func runMultiObjectiveOptimization()
        async throws
        -> [TestFlowDiagnostic]
    {
        let quality = AgentInferenceRealization(
            strategy: .direct,
            modelSelection: .executor,
            instructions: "quality",
            budget: .singleAttempt
        )
        let balanced = AgentInferenceRealization(
            strategy: .direct,
            modelSelection: .executor,
            instructions: "balanced",
            budget: .singleAttempt
        )
        let cheap = AgentInferenceRealization(
            strategy: .direct,
            modelSelection: .executor,
            instructions: "cheap",
            budget: .singleAttempt
        )
        let inferenceCandidates = [
            AgentInferenceRealizationCandidate(
                identifier: "quality",
                realization: quality
            ),
            AgentInferenceRealizationCandidate(
                identifier: "balanced",
                realization: balanced
            ),
            AgentInferenceRealizationCandidate(
                identifier: "cheap",
                realization: cheap
            ),
        ]
        let inferenceDataset =
            try AgentInferenceOptimizationDataset<
                MultiObjectiveInference
            >.parse(
                training: [
                    .init(
                        input: "alpha",
                        expectedOutput: "ALPHA"
                    ),
                    .init(
                        input: "beta",
                        expectedOutput: "BETA"
                    ),
                ],
                evaluation: [
                    .init(
                        input: "alpha",
                        expectedOutput: "ALPHA"
                    ),
                ]
            )
        let weights = try AgentOptimizationMultiObjectiveWeights.parse(
            quality: 0.40,
            totalTokens: 0.20,
            estimatedUsd: 0.20,
            latencySeconds: 0.20
        )
        let inferenceOptimizer = AgentInferenceMultiObjectiveOptimizer(
            executor: MultiObjectiveFixtureExecutor(),
            objective: MultiObjectiveInferenceObjective(),
            resources: MultiObjectiveFixtureResourceEstimator()
        )
        let inferenceReport = try await inferenceOptimizer.optimize(
            MultiObjectiveInference.self,
            dataset: inferenceDataset,
            candidates: inferenceCandidates,
            weights: weights
        )

        try Expect.equal(
            inferenceReport.optimization.selectedCandidate.identifier,
            AgentInferenceRealizationCandidateIdentifier(
                "balanced"
            ),
            "multi-objective inference selection can trade a small quality reduction for large token, cost, and latency improvements"
        )
        try Expect.equal(
            inferenceReport.optimization.candidates[0].quality.mean.value,
            1.0,
            "quality-only candidate remains the semantic quality winner"
        )
        try Expect.equal(
            inferenceReport.optimization.candidates[1].resources.totalTokens,
            40,
            "resource metrics aggregate across training trials"
        )
        try Expect.equal(
            inferenceReport.optimization.candidates[1].resources.estimatedUsd,
            4.0,
            "candidate cost aggregates across training trials"
        )
        try Expect.equal(
            inferenceReport.evaluation.quality.candidate.identifier,
            AgentInferenceRealizationCandidateIdentifier(
                "balanced"
            ),
            "held-out evaluation runs the multi-objective selected candidate"
        )

        let programCandidates: [
            ProgramOptimization.Candidate<MultiObjectiveProgram>
        ] = try [
            (
                "program_quality",
                quality
            ),
            (
                "program_balanced",
                balanced
            ),
            (
                "program_cheap",
                cheap
            ),
        ].map { id, realization in
            ProgramOptimization.Candidate(
                id: ProgramOptimization.CandidateID(
                    rawValue: id
                ),
                realization: AgentProgramRealization(
                    id: AgentProgramRealizationIdentifier(
                        rawValue: "fixture.\(id)"
                    ),
                    inferences: try AgentProgramInferenceBindings(
                        [
                            AgentInferenceRealizationBinding(
                                site: "transform",
                                inference: MultiObjectiveInference
                                    .definition.identifier,
                                realization: realization
                            ),
                        ]
                    )
                )
            )
        }
        let programDataset =
            try ProgramOptimization.Dataset<MultiObjectiveProgram>.parse(
                training: [
                    .init(
                        input: "alpha",
                        expectedOutput: "ALPHA"
                    ),
                    .init(
                        input: "beta",
                        expectedOutput: "BETA"
                    ),
                ],
                evaluation: [
                    .init(
                        input: "alpha",
                        expectedOutput: "ALPHA"
                    ),
                ]
            )
        let programOptimizer = ProgramMultiObjectiveOptimizer(
            program: MultiObjectiveProgram(),
            inferenceExecutor: MultiObjectiveFixtureExecutor(),
            objective: MultiObjectiveProgramObjective(),
            resources: MultiObjectiveFixtureResourceEstimator()
        )
        let programReport = try await programOptimizer.optimize(
            dataset: programDataset,
            candidates: programCandidates,
            weights: weights
        )

        try Expect.equal(
            programReport.optimization.selected.id,
            ProgramOptimization.CandidateID(
                rawValue: "program_balanced"
            ),
            "whole-program multi-objective selection uses captured inference execution provenance"
        )
        try Expect.equal(
            programReport.optimization.candidates[1]
                .resources.totalTokens,
            40,
            "whole-program resource aggregation sees inference executions hidden behind AgentProgramContext"
        )
        try Expect.equal(
            programReport.optimization.trials[0]
                .executions.count,
            1,
            "program trials preserve the concrete inference execution records used for resource scoring"
        )
        try Expect.equal(
            programReport.evaluation.quality.candidate.id,
            ProgramOptimization.CandidateID(
                rawValue: "program_balanced"
            ),
            "whole-program held-out evaluation preserves the multi-objective winner"
        )

        var emptyWeightsRejected = false

        do {
            _ = try AgentOptimizationMultiObjectiveWeights.parse(
                quality: 0,
                totalTokens: 0,
                estimatedUsd: 0,
                latencySeconds: 0
            )
        } catch AgentOptimizationMultiObjectiveWeightsParsingError
            .noWeightedMetrics {
            emptyWeightsRejected = true
        }

        try Expect.equal(
            emptyWeightsRejected,
            true,
            "multi-objective weights are valid by construction"
        )

        let defaultResources = AgentOptimizationExecutionResourceEstimator()
        let missingCost = try defaultResources.estimate(
            executions: [],
            measuredDurationSeconds: 0
        )
        var unavailableCostRejected = false

        do {
            _ = try AgentOptimizationMultiObjectiveRanking.rank(
                [
                    AgentOptimizationMultiObjectiveMeasurement(
                        quality: try AgentInferenceOptimizationScore(
                            value: 1
                        ),
                        resources: missingCost
                    ),
                ],
                weights: try AgentOptimizationMultiObjectiveWeights.parse(
                    quality: 1,
                    estimatedUsd: 1
                )
            )
        } catch AgentOptimizationMultiObjectiveRankingError
            .metricUnavailable(.estimated_usd) {
            unavailableCostRejected = true
        }

        try Expect.equal(
            unavailableCostRejected,
            true,
            "a weighted resource dimension must actually be available rather than silently treated as zero"
        )

        return [
            .field(
                "inference_selected",
                inferenceReport.optimization
                    .selectedCandidate.identifier.rawValue
            ),
            .field(
                "program_selected",
                programReport.optimization.selected.id.rawValue
            ),
            .field(
                "balanced_tokens",
                String(
                    programReport.optimization.candidates[1]
                        .resources.totalTokens
                    ?? -1
                )
            ),
            .field(
                "balanced_cost",
                String(
                    programReport.optimization.candidates[1]
                        .resources.estimatedUsd
                    ?? -1
                )
            ),
            .field(
                "balanced_latency",
                String(
                    programReport.optimization.candidates[1]
                        .resources.latencySeconds
                    ?? -1
                )
            ),
            .field(
                "invalid_weights_rejected",
                String(emptyWeightsRejected)
            ),
            .field(
                "missing_cost_rejected",
                String(unavailableCostRejected)
            ),
        ]
    }
}
