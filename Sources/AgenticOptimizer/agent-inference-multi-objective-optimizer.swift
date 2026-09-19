import Agentic
import AgenticInference

public struct InferenceMultiObjectiveCandidateResult:
    Sendable
{
    public var quality: InferenceOptimizationCandidateResult
    public var resources: OptimizationResourceMetrics
    public var utility: InferenceOptimizationScore

    public init(
        quality: InferenceOptimizationCandidateResult,
        resources: OptimizationResourceMetrics,
        utility: InferenceOptimizationScore
    ) {
        self.quality = quality
        self.resources = resources
        self.utility = utility
    }
}

public struct InferenceMultiObjectiveResult:
    Sendable
{
    public var objective: InferenceOptimizationObjectiveIdentifier
    public var weights: OptimizationMultiObjectiveWeights
    public var selectedCandidate: InferenceRealizationCandidate
    public var candidates: [InferenceMultiObjectiveCandidateResult]
    public var trials: [InferenceOptimizationTrial]

    public init(
        objective: InferenceOptimizationObjectiveIdentifier,
        weights: OptimizationMultiObjectiveWeights,
        selectedCandidate: InferenceRealizationCandidate,
        candidates: [InferenceMultiObjectiveCandidateResult],
        trials: [InferenceOptimizationTrial]
    ) {
        self.objective = objective
        self.weights = weights
        self.selectedCandidate = selectedCandidate
        self.candidates = candidates
        self.trials = trials
    }
}

public struct InferenceMultiObjectiveEvaluation:
    Sendable
{
    public var quality: InferenceOptimizationEvaluation
    public var resources: OptimizationResourceMetrics

    public init(
        quality: InferenceOptimizationEvaluation,
        resources: OptimizationResourceMetrics
    ) {
        self.quality = quality
        self.resources = resources
    }
}

public struct InferenceMultiObjectiveReport:
    Sendable
{
    public var optimization: InferenceMultiObjectiveResult
    public var evaluation: InferenceMultiObjectiveEvaluation

    public init(
        optimization: InferenceMultiObjectiveResult,
        evaluation: InferenceMultiObjectiveEvaluation
    ) {
        self.optimization = optimization
        self.evaluation = evaluation
    }
}

public struct InferenceMultiObjectiveOptimizer:
    Sendable
{
    private let search: InferenceRealizationSearch
    private let resources: any OptimizationResourceEstimating

    public init(
        executor: any InferenceExecuting,
        objective: any InferenceOptimizationObjective,
        resources: any OptimizationResourceEstimating =
            OptimizationExecutionResourceEstimator()
    ) {
        self.search = InferenceRealizationSearch(
            executor: executor,
            objective: objective
        )
        self.resources = resources
    }

    public func optimize<InferenceType: Inference>(
        _ inference: InferenceType.Type,
        dataset: InferenceOptimizationDataset<InferenceType>,
        candidates: [InferenceRealizationCandidate],
        weights: OptimizationMultiObjectiveWeights
    ) async throws -> InferenceMultiObjectiveReport {
        let optimization = try await optimize(
            inference,
            examples: dataset.training,
            candidates: candidates,
            weights: weights
        )
        let qualityEvaluation = try await search.evaluate(
            inference,
            candidate: optimization.selectedCandidate,
            examples: dataset.evaluation
        )
        let resourceEvaluation = try candidateResources(
            qualityEvaluation.trials
        )

        return InferenceMultiObjectiveReport(
            optimization: optimization,
            evaluation: InferenceMultiObjectiveEvaluation(
                quality: qualityEvaluation,
                resources: resourceEvaluation
            )
        )
    }

    public func optimize<InferenceType: Inference>(
        _ inference: InferenceType.Type,
        examples: InferenceOptimizationExamples<InferenceType>,
        candidates: [InferenceRealizationCandidate],
        weights: OptimizationMultiObjectiveWeights
    ) async throws -> InferenceMultiObjectiveResult {
        let qualityResult = try await search.optimize(
            inference,
            problem: InferenceOptimizationProblem(
                examples: examples,
                candidates: try InferenceRealizationCandidates.parse(
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
            InferenceMultiObjectiveCandidateResult(
                quality: qualityResult.candidates[index],
                resources: resourceMetrics[index],
                utility: ranking.utilities[index]
            )
        }

        return InferenceMultiObjectiveResult(
            objective: qualityResult.objective,
            weights: weights,
            selectedCandidate:
                qualityResult.candidates[
                    ranking.selectedIndex
                ].candidate,
            candidates: assessed,
            trials: qualityResult.trials
        )
    }

    private func candidateResources(
        _ trials: [InferenceOptimizationTrial]
    ) throws -> OptimizationResourceMetrics {
        let metrics = try trials.map { trial in
            try resources.estimate(
                executions: [
                    trial.execution,
                ],
                measuredDurationSeconds: trial.durationSeconds
            )
        }

        return try OptimizationMultiObjectiveRanking.aggregate(
            metrics
        )
    }
}