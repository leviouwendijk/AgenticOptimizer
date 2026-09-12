import AgenticInference

public struct AgentInferenceRealizationSearch: Sendable {
    private let executor: any AgentInferenceExecuting
    private let objective: any AgentInferenceOptimizationObjective

    public init(
        executor: any AgentInferenceExecuting,
        objective: any AgentInferenceOptimizationObjective
    ) {
        self.executor = executor
        self.objective = objective
    }

    public func optimize<Inference: AgentInference>(
        _ inference: Inference.Type,
        dataset: AgentInferenceOptimizationDataset<Inference>,
        seed: AgentInferenceRealization,
        generator: any AgentInferenceRealizationCandidateGenerating
    ) async throws -> AgentInferenceOptimizationReport {
        let generated = try await generator.generate(
            inference,
            examples: dataset.training.values,
            seed: seed
        )
        let optimization = try await optimize(
            inference,
            problem: AgentInferenceOptimizationProblem(
                examples: dataset.training,
                candidates: try AgentInferenceRealizationCandidates.parse(
                    generated
                )
            )
        )
        let evaluation = try await evaluate(
            inference,
            candidate: optimization.selectedCandidate,
            examples: dataset.evaluation
        )

        return AgentInferenceOptimizationReport(
            optimization: optimization,
            evaluation: evaluation
        )
    }

    public func optimize<Inference: AgentInference>(
        _ inference: Inference.Type,
        dataset: AgentInferenceOptimizationDataset<Inference>,
        candidates: [AgentInferenceRealizationCandidate]
    ) async throws -> AgentInferenceOptimizationReport {
        let optimization = try await optimize(
            inference,
            problem: AgentInferenceOptimizationProblem(
                examples: dataset.training,
                candidates: try AgentInferenceRealizationCandidates.parse(
                    candidates
                )
            )
        )
        let evaluation = try await evaluate(
            inference,
            candidate: optimization.selectedCandidate,
            examples: dataset.evaluation
        )

        return AgentInferenceOptimizationReport(
            optimization: optimization,
            evaluation: evaluation
        )
    }

    public func optimize<Inference: AgentInference>(
        _ inference: Inference.Type,
        examples: [AgentInferenceOptimizationExample<Inference>],
        seed: AgentInferenceRealization,
        generator: any AgentInferenceRealizationCandidateGenerating
    ) async throws -> AgentInferenceOptimizationResult {
        let parsedExamples =
            try AgentInferenceOptimizationExamples<Inference>.parse(
                examples
            )
        let generated = try await generator.generate(
            inference,
            examples: parsedExamples.values,
            seed: seed
        )
        let problem = AgentInferenceOptimizationProblem(
            examples: parsedExamples,
            candidates: try AgentInferenceRealizationCandidates.parse(
                generated
            )
        )

        return try await optimize(
            inference,
            problem: problem
        )
    }

    public func optimize<Inference: AgentInference>(
        _ inference: Inference.Type,
        examples: [AgentInferenceOptimizationExample<Inference>],
        candidates: [AgentInferenceRealizationCandidate]
    ) async throws -> AgentInferenceOptimizationResult {
        try await optimize(
            inference,
            problem: AgentInferenceOptimizationProblem.parse(
                examples: examples,
                candidates: candidates
            )
        )
    }

    public func optimize<Inference: AgentInference>(
        _ inference: Inference.Type,
        problem: AgentInferenceOptimizationProblem<Inference>
    ) async throws -> AgentInferenceOptimizationResult {
        var trials: [AgentInferenceOptimizationTrial] = []
        var candidateResults: [AgentInferenceOptimizationCandidateResult] = []

        var selectedCandidate = problem.candidates.initial
        var selectedMean: AgentInferenceOptimizationScore?

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
                AgentInferenceOptimizationCandidateResult(
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

        return AgentInferenceOptimizationResult(
            inference: inference.definition.identifier,
            objective: objective.identifier,
            selectedCandidate: selectedCandidate,
            candidates: candidateResults,
            trials: trials
        )
    }

    public func evaluate<Inference: AgentInference>(
        _ inference: Inference.Type,
        candidate: AgentInferenceRealizationCandidate,
        examples: AgentInferenceOptimizationExamples<Inference>
    ) async throws -> AgentInferenceOptimizationEvaluation {
        var trials: [AgentInferenceOptimizationTrial] = []
        var meanValue = 0.0
        let exampleCount = Double(
            examples.count
        )

        for (exampleIndex, example) in examples.enumerated() {
            let execution = try await executor.execute(
                inference,
                input: example.input,
                realization: candidate.realization
            )
            let score = try await objective.score(
                inference,
                example: example,
                result: execution
            )

            meanValue += score.value / exampleCount

            trials.append(
                AgentInferenceOptimizationTrial(
                    candidate: candidate.identifier,
                    exampleIndex: exampleIndex,
                    score: score,
                    execution: execution.record
                )
            )
        }

        return AgentInferenceOptimizationEvaluation(
            candidate: candidate,
            mean: try AgentInferenceOptimizationScore(
                value: meanValue
            ),
            trials: trials
        )
    }
}
