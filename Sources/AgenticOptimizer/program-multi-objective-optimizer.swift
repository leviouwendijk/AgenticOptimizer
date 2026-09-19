import Agentic
import AgenticInference
import AgenticPrograms

public extension ProgramOptimization {
    struct MultiObjectiveCandidateResult<ProgramType: Program>:
        Sendable
    {
        public var quality: CandidateResult<ProgramType>
        public var resources: OptimizationResourceMetrics
        public var utility: InferenceOptimizationScore

        public init(
            quality: CandidateResult<ProgramType>,
            resources: OptimizationResourceMetrics,
            utility: InferenceOptimizationScore
        ) {
            self.quality = quality
            self.resources = resources
            self.utility = utility
        }
    }

    struct MultiObjectiveResult<ProgramType: Program>:
        Sendable
    {
        public var objective: ObjectiveID
        public var weights: OptimizationMultiObjectiveWeights
        public var selected: Candidate<ProgramType>
        public var candidates: [MultiObjectiveCandidateResult<ProgramType>]
        public var trials: [Trial]

        public init(
            objective: ObjectiveID,
            weights: OptimizationMultiObjectiveWeights,
            selected: Candidate<ProgramType>,
            candidates: [MultiObjectiveCandidateResult<ProgramType>],
            trials: [Trial]
        ) {
            self.objective = objective
            self.weights = weights
            self.selected = selected
            self.candidates = candidates
            self.trials = trials
        }
    }

    struct MultiObjectiveEvaluation<ProgramType: Program>:
        Sendable
    {
        public var quality: Evaluation<ProgramType>
        public var resources: OptimizationResourceMetrics

        public init(
            quality: Evaluation<ProgramType>,
            resources: OptimizationResourceMetrics
        ) {
            self.quality = quality
            self.resources = resources
        }
    }

    struct MultiObjectiveReport<ProgramType: Program>:
        Sendable
    {
        public var optimization: MultiObjectiveResult<ProgramType>
        public var evaluation: MultiObjectiveEvaluation<ProgramType>

        public init(
            optimization: MultiObjectiveResult<ProgramType>,
            evaluation: MultiObjectiveEvaluation<ProgramType>
        ) {
            self.optimization = optimization
            self.evaluation = evaluation
        }
    }
}

public struct ProgramMultiObjectiveOptimizer<ProgramType: Program>:
    Sendable
{
    private let search: ProgramRealizationSearch<ProgramType>
    private let resources: any OptimizationResourceEstimating

    public init(
        program: ProgramType,
        inferenceExecutor: any InferenceExecuting,
        objective: any ProgramOptimization.Objective,
        resources: any OptimizationResourceEstimating =
            OptimizationExecutionResourceEstimator()
    ) {
        self.search = ProgramRealizationSearch(
            program: program,
            inferenceExecutor: inferenceExecutor,
            objective: objective
        )
        self.resources = resources
    }

    public func optimize(
        dataset: ProgramOptimization.Dataset<ProgramType>,
        candidates: [ProgramOptimization.Candidate<ProgramType>],
        weights: OptimizationMultiObjectiveWeights
    ) async throws -> ProgramOptimization.MultiObjectiveReport<ProgramType> {
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
        examples: ProgramOptimization.Examples<ProgramType>,
        candidates: [ProgramOptimization.Candidate<ProgramType>],
        weights: OptimizationMultiObjectiveWeights
    ) async throws -> ProgramOptimization.MultiObjectiveResult<ProgramType> {
        let qualityResult = try await search.optimize(
            problem: ProgramOptimization.Problem(
                examples: examples,
                candidates: try ProgramOptimization
                    .Candidates<ProgramType>
                    .parse(
                        candidates
                    )
            )
        )
        var measurements: [OptimizationMultiObjectiveMeasurement] = []
        var resourceMetrics: [OptimizationResourceMetrics] = []

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
                OptimizationMultiObjectiveMeasurement(
                    quality: candidate.mean,
                    resources: resources
                )
            )
        }

        let ranking = try OptimizationMultiObjectiveRanking.rank(
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
    ) throws -> OptimizationResourceMetrics {
        let metrics = try trials.map { trial in
            try resources.estimate(
                executions: trial.executions,
                measuredDurationSeconds: trial.durationSeconds
            )
        }

        return try OptimizationMultiObjectiveRanking.aggregate(
            metrics
        )
    }
}