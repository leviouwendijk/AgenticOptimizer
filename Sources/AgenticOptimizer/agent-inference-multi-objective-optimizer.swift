import AgenticInference

public struct AgentInferenceMultiObjectiveCandidateResult:
    Sendable
{
    public var quality: AgentInferenceOptimizationCandidateResult
    public var resources: AgentOptimizationResourceMetrics
    public var utility: AgentInferenceOptimizationScore

    public init(
        quality: AgentInferenceOptimizationCandidateResult,
        resources: AgentOptimizationResourceMetrics,
        utility: AgentInferenceOptimizationScore
    ) {
        self.quality = quality
        self.resources = resources
        self.utility = utility
    }
}

public struct AgentInferenceMultiObjectiveResult:
    Sendable
{
    public var objective: AgentInferenceOptimizationObjectiveIdentifier
    public var weights: AgentOptimizationMultiObjectiveWeights
    public var selectedCandidate: AgentInferenceRealizationCandidate
    public var candidates: [AgentInferenceMultiObjectiveCandidateResult]
    public var trials: [AgentInferenceOptimizationTrial]

    public init(
        objective: AgentInferenceOptimizationObjectiveIdentifier,
        weights: AgentOptimizationMultiObjectiveWeights,
        selectedCandidate: AgentInferenceRealizationCandidate,
        candidates: [AgentInferenceMultiObjectiveCandidateResult],
        trials: [AgentInferenceOptimizationTrial]
    ) {
        self.objective = objective
        self.weights = weights
        self.selectedCandidate = selectedCandidate
        self.candidates = candidates
        self.trials = trials
    }
}

public struct AgentInferenceMultiObjectiveEvaluation:
    Sendable
{
    public var quality: AgentInferenceOptimizationEvaluation
    public var resources: AgentOptimizationResourceMetrics

    public init(
        quality: AgentInferenceOptimizationEvaluation,
        resources: AgentOptimizationResourceMetrics
    ) {
        self.quality = quality
        self.resources = resources
    }
}

public struct AgentInferenceMultiObjectiveReport:
    Sendable
{
    public var optimization: AgentInferenceMultiObjectiveResult
    public var evaluation: AgentInferenceMultiObjectiveEvaluation

    public init(
        optimization: AgentInferenceMultiObjectiveResult,
        evaluation: AgentInferenceMultiObjectiveEvaluation
    ) {
        self.optimization = optimization
        self.evaluation = evaluation
    }
}

public struct AgentInferenceMultiObjectiveOptimizer:
    Sendable
{
    private let search: AgentInferenceRealizationSearch
    private let resources: any AgentOptimizationResourceEstimating

    public init(
        executor: any AgentInferenceExecuting,
        objective: any AgentInferenceOptimizationObjective,
        resources: any AgentOptimizationResourceEstimating =
            AgentOptimizationExecutionResourceEstimator()
    ) {
        self.search = AgentInferenceRealizationSearch(
            executor: executor,
            objective: objective
        )
        self.resources = resources
    }

    public func optimize<Inference: AgentInference>(
        _ inference: Inference.Type,
        dataset: AgentInferenceOptimizationDataset<Inference>,
        candidates: [AgentInferenceRealizationCandidate],
        weights: AgentOptimizationMultiObjectiveWeights
    ) async throws -> AgentInferenceMultiObjectiveReport {
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

        return AgentInferenceMultiObjectiveReport(
            optimization: optimization,
            evaluation: AgentInferenceMultiObjectiveEvaluation(
                quality: qualityEvaluation,
                resources: resourceEvaluation
            )
        )
    }

    public func optimize<Inference: AgentInference>(
        _ inference: Inference.Type,
        examples: AgentInferenceOptimizationExamples<Inference>,
        candidates: [AgentInferenceRealizationCandidate],
        weights: AgentOptimizationMultiObjectiveWeights
    ) async throws -> AgentInferenceMultiObjectiveResult {
        let qualityResult = try await search.optimize(
            inference,
            problem: AgentInferenceOptimizationProblem(
                examples: examples,
                candidates: try AgentInferenceRealizationCandidates.parse(
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
            AgentInferenceMultiObjectiveCandidateResult(
                quality: qualityResult.candidates[index],
                resources: resourceMetrics[index],
                utility: ranking.utilities[index]
            )
        }

        return AgentInferenceMultiObjectiveResult(
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
        _ trials: [AgentInferenceOptimizationTrial]
    ) throws -> AgentOptimizationResourceMetrics {
        let metrics = try trials.map { trial in
            try resources.estimate(
                executions: [
                    trial.execution,
                ],
                measuredDurationSeconds: trial.durationSeconds
            )
        }

        return try AgentOptimizationMultiObjectiveRanking.aggregate(
            metrics
        )
    }
}
