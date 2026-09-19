import Agentic
import AgenticInference

public struct InferenceRealizationSearch: Sendable {
    private let executor: any InferenceExecuting
    private let objective: any InferenceOptimizationObjective

    public init(
        executor: any InferenceExecuting,
        objective: any InferenceOptimizationObjective
    ) {
        self.executor = executor
        self.objective = objective
    }

    public func optimize<InferenceType: Inference>(
        _ inference: InferenceType.Type,
        dataset: InferenceOptimizationDataset<InferenceType>,
        seed: InferenceRealizationConfiguration,
        generator: any InferenceRealizationCandidateGenerating
    ) async throws -> InferenceOptimizationReport {
        let generated = try await generator.generate(
            inference,
            examples: dataset.training.values,
            seed: seed
        )
        let optimization = try await optimize(
            inference,
            problem: InferenceOptimizationProblem(
                examples: dataset.training,
                candidates: try InferenceRealizationCandidates.parse(
                    generated
                )
            )
        )
        let evaluation = try await evaluate(
            inference,
            candidate: optimization.selectedCandidate,
            examples: dataset.evaluation
        )

        return InferenceOptimizationReport(
            optimization: optimization,
            evaluation: evaluation
        )
    }

    public func optimize<InferenceType: Inference>(
        _ inference: InferenceType.Type,
        dataset: InferenceOptimizationDataset<InferenceType>,
        candidates: [InferenceRealizationCandidate]
    ) async throws -> InferenceOptimizationReport {
        let optimization = try await optimize(
            inference,
            problem: InferenceOptimizationProblem(
                examples: dataset.training,
                candidates: try InferenceRealizationCandidates.parse(
                    candidates
                )
            )
        )
        let evaluation = try await evaluate(
            inference,
            candidate: optimization.selectedCandidate,
            examples: dataset.evaluation
        )

        return InferenceOptimizationReport(
            optimization: optimization,
            evaluation: evaluation
        )
    }

    public func optimize<InferenceType: Inference>(
        _ inference: InferenceType.Type,
        examples: [InferenceOptimizationExample<InferenceType>],
        seed: InferenceRealizationConfiguration,
        generator: any InferenceRealizationCandidateGenerating
    ) async throws -> InferenceOptimizationResult {
        let parsedExamples =
            try InferenceOptimizationExamples<InferenceType>.parse(
                examples
            )
        let generated = try await generator.generate(
            inference,
            examples: parsedExamples.values,
            seed: seed
        )
        let problem = InferenceOptimizationProblem(
            examples: parsedExamples,
            candidates: try InferenceRealizationCandidates.parse(
                generated
            )
        )

        return try await optimize(
            inference,
            problem: problem
        )
    }

    public func optimize<InferenceType: Inference>(
        _ inference: InferenceType.Type,
        examples: [InferenceOptimizationExample<InferenceType>],
        candidates: [InferenceRealizationCandidate]
    ) async throws -> InferenceOptimizationResult {
        try await optimize(
            inference,
            problem: InferenceOptimizationProblem.parse(
                examples: examples,
                candidates: candidates
            )
        )
    }

    public func optimize<InferenceType: Inference>(
        _ inference: InferenceType.Type,
        problem: InferenceOptimizationProblem<InferenceType>
    ) async throws -> InferenceOptimizationResult {
        var trials: [InferenceOptimizationTrial] = []
        var candidateResults: [InferenceOptimizationCandidateResult] = []

        var selectedCandidate = problem.candidates.initial
        var selectedMean: InferenceOptimizationScore?

        for candidate in problem.candidates {
            let evaluation = try await evaluate(
                inference,
                candidate: candidate,
                examples: problem.examples
            )
            let firstTrialIndex = trials.count

            trials.append(
                contentsOf: evaluation.trials
            )

            candidateResults.append(
                InferenceOptimizationCandidateResult(
                    candidate: candidate,
                    mean: evaluation.mean,
                    trialIndexes: Array(
                        firstTrialIndex..<trials.count
                    )
                )
            )

            if let currentSelectedMean = selectedMean {
                if evaluation.mean.value > currentSelectedMean.value {
                    selectedCandidate = candidate
                    selectedMean = evaluation.mean
                }
            } else {
                selectedCandidate = candidate
                selectedMean = evaluation.mean
            }
        }

        return InferenceOptimizationResult(
            inference: inference.definition.identifier,
            objective: objective.identifier,
            selectedCandidate: selectedCandidate,
            candidates: candidateResults,
            trials: trials
        )
    }

    public func evaluate<InferenceType: Inference>(
        _ inference: InferenceType.Type,
        candidate: InferenceRealizationCandidate,
        examples: InferenceOptimizationExamples<InferenceType>
    ) async throws -> InferenceOptimizationEvaluation {
        var trials: [InferenceOptimizationTrial] = []
        var meanValue = 0.0
        let exampleCount = Double(
            examples.count
        )
        let clock = ContinuousClock()

        for (exampleIndex, example) in examples.enumerated() {
            let startedAt = clock.now
            let execution = try await executor.execute(
                inference,
                input: example.input,
                realization: candidate.realization
            )
            let duration = startedAt.duration(
                to: clock.now
            )
            let durationSeconds =
                max(
                    0,
                    Double(duration.components.seconds)
                        + Double(duration.components.attoseconds)
                            / 1_000_000_000_000_000_000
                )
            let score = try await objective.score(
                inference,
                example: example,
                result: execution
            )

            meanValue += score.value / exampleCount

            trials.append(
                InferenceOptimizationTrial(
                    candidate: candidate.identifier,
                    exampleIndex: exampleIndex,
                    score: score,
                    execution: execution.record,
                    durationSeconds: durationSeconds
                )
            )
        }

        return InferenceOptimizationEvaluation(
            candidate: candidate,
            mean: try InferenceOptimizationScore(
                value: meanValue
            ),
            trials: trials
        )
    }
}