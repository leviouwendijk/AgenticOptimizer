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

        let exampleCount = Double(
            problem.examples.count
        )

        for candidate in problem.candidates {
            let firstTrialIndex = trials.count
            var meanValue = 0.0

            for (exampleIndex, example) in problem.examples.enumerated() {
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

            let mean = try AgentInferenceOptimizationScore(
                value: meanValue
            )
            let trialIndexes = Array(
                firstTrialIndex..<trials.count
            )

            candidateResults.append(
                AgentInferenceOptimizationCandidateResult(
                    candidate: candidate,
                    mean: mean,
                    trialIndexes: trialIndexes
                )
            )

            if let currentSelectedMean = selectedMean {
                if mean.value > currentSelectedMean.value {
                    selectedCandidate = candidate
                    selectedMean = mean
                }
            } else {
                selectedCandidate = candidate
                selectedMean = mean
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
}
