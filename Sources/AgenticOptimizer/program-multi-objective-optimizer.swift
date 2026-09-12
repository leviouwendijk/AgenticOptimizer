import AgenticInference
import AgenticPrograms

public extension ProgramOptimization {
    struct MultiObjectiveCandidateResult<Program: AgentProgram>:
        Sendable
    {
        public var quality: CandidateResult<Program>
        public var resources: AgentOptimizationResourceMetrics
        public var utility: AgentInferenceOptimizationScore

        public init(
            quality: CandidateResult<Program>,
            resources: AgentOptimizationResourceMetrics,
            utility: AgentInferenceOptimizationScore
        ) {
            self.quality = quality
            self.resources = resources
            self.utility = utility
        }
    }

    struct MultiObjectiveResult<Program: AgentProgram>:
        Sendable
    {
        public var objective: ObjectiveID
        public var weights: AgentOptimizationMultiObjectiveWeights
        public var selected: Candidate<Program>
        public var candidates: [MultiObjectiveCandidateResult<Program>]
        public var trials: [Trial]

        public init(
            objective: ObjectiveID,
            weights: AgentOptimizationMultiObjectiveWeights,
            selected: Candidate<Program>,
            candidates: [MultiObjectiveCandidateResult<Program>],
            trials: [Trial]
        ) {
            self.objective = objective
            self.weights = weights
            self.selected = selected
            self.candidates = candidates
            self.trials = trials
        }
    }

    struct MultiObjectiveEvaluation<Program: AgentProgram>:
        Sendable
    {
        public var quality: Evaluation<Program>
        public var resources: AgentOptimizationResourceMetrics

        public init(
            quality: Evaluation<Program>,
            resources: AgentOptimizationResourceMetrics
        ) {
            self.quality = quality
            self.resources = resources
        }
    }

    struct MultiObjectiveReport<Program: AgentProgram>:
        Sendable
    {
        public var optimization: MultiObjectiveResult<Program>
        public var evaluation: MultiObjectiveEvaluation<Program>

        public init(
            optimization: MultiObjectiveResult<Program>,
            evaluation: MultiObjectiveEvaluation<Program>
        ) {
            self.optimization = optimization
            self.evaluation = evaluation
        }
    }
}

public struct ProgramMultiObjectiveOptimizer<Program: AgentProgram>:
    Sendable
{
    private let search: ProgramRealizationSearch<Program>
    private let resources: any AgentOptimizationResourceEstimating

    public init(
        program: Program,
        inferenceExecutor: any AgentInferenceExecuting,
        objective: any ProgramOptimization.Objective,
        resources: any AgentOptimizationResourceEstimating =
            AgentOptimizationExecutionResourceEstimator()
    ) {
        self.search = ProgramRealizationSearch(
            program: program,
            inferenceExecutor: inferenceExecutor,
            objective: objective
        )
        self.resources = resources
    }

    public func optimize(
        dataset: ProgramOptimization.Dataset<Program>,
        candidates: [ProgramOptimization.Candidate<Program>],
        weights: AgentOptimizationMultiObjectiveWeights
    ) async throws -> ProgramOptimization.MultiObjectiveReport<Program> {
        let optimization = try await optimize(
            examples: dataset.training,
            candidates: candidates,
            weights: weights
        )
        let qualityEvaluation = try await search.evaluate(
            candidate: optimization.selected,
            examples: dataset.evaluation
        )
        let resourceEvaluation = try candidateResources(
            qualityEvaluation.trials
        )

        return ProgramOptimization.MultiObjectiveReport(
            optimization: optimization,
            evaluation: ProgramOptimization.MultiObjectiveEvaluation(
                quality: qualityEvaluation,
                resources: resourceEvaluation
            )
        )
    }

    public func optimize(
        examples: ProgramOptimization.Examples<Program>,
        candidates: [ProgramOptimization.Candidate<Program>],
        weights: AgentOptimizationMultiObjectiveWeights
    ) async throws -> ProgramOptimization.MultiObjectiveResult<Program> {
        let qualityResult = try await search.optimize(
            problem: ProgramOptimization.Problem(
                examples: examples,
                candidates: try ProgramOptimization
                    .Candidates<Program>
                    .parse(
                        candidates
                    )
            )
        )
        var measurements: [AgentOptimizationMultiObjectiveMeasurement] = []
        var resourceMetrics: [AgentOptimizationResourceMetrics] = []

        for candidate in qualityResult.candidates {
            let trials = candidate.trialIndexes.map {
                qualityResult.trials[$0]
            }
            let resources = try candidateResources(
                trials
            )

            resourceMetrics.append(
                resources
            )
            measurements.append(
                AgentOptimizationMultiObjectiveMeasurement(
                    quality: candidate.mean,
                    resources: resources
                )
            )
        }

        let ranking = try AgentOptimizationMultiObjectiveRanking.rank(
            measurements,
            weights: weights
        )
        let assessed = qualityResult.candidates.indices.map { index in
            ProgramOptimization.MultiObjectiveCandidateResult(
                quality: qualityResult.candidates[index],
                resources: resourceMetrics[index],
                utility: ranking.utilities[index]
            )
        }

        return ProgramOptimization.MultiObjectiveResult(
            objective: qualityResult.objective,
            weights: weights,
            selected:
                qualityResult.candidates[
                    ranking.selectedIndex
                ].candidate,
            candidates: assessed,
            trials: qualityResult.trials
        )
    }

    private func candidateResources(
        _ trials: [ProgramOptimization.Trial]
    ) throws -> AgentOptimizationResourceMetrics {
        let metrics = try trials.map { trial in
            try resources.estimate(
                executions: trial.executions,
                measuredDurationSeconds: trial.durationSeconds
            )
        }

        return try AgentOptimizationMultiObjectiveRanking.aggregate(
            metrics
        )
    }
}
