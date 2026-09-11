import AgenticInference
import Foundation

public enum AgentInferenceRealizationSearchError:
    Error,
    Sendable,
    LocalizedError
{
    case noCandidates
    case noExamples
    case invalidScore(
        objective: AgentInferenceOptimizationObjectiveIdentifier,
        candidate: AgentInferenceRealizationCandidateIdentifier,
        exampleIndex: Int
    )
    case noSelectionProduced

    public var errorDescription: String? {
        switch self {
        case .noCandidates:
            return "Inference realization optimization requires at least one candidate."

        case .noExamples:
            return "Inference realization optimization requires at least one example."

        case .invalidScore(
            let objective,
            let candidate,
            let exampleIndex
        ):
            return "Optimization objective '\(objective.rawValue)' returned a non-finite score for candidate '\(candidate.rawValue)' on example \(exampleIndex)."

        case .noSelectionProduced:
            return "Inference realization optimization completed without selecting a candidate."
        }
    }
}

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
        candidates: [AgentInferenceRealizationCandidate]
    ) async throws -> AgentInferenceOptimizationResult {
        guard !candidates.isEmpty else {
            throw AgentInferenceRealizationSearchError.noCandidates
        }

        guard !examples.isEmpty else {
            throw AgentInferenceRealizationSearchError.noExamples
        }

        var trials: [AgentInferenceOptimizationTrial] = []
        var candidateResults: [AgentInferenceOptimizationCandidateResult] = []

        var selectedCandidate: AgentInferenceRealizationCandidate?
        var selectedMeanScore: Double?

        for candidate in candidates {
            let firstTrialIndex = trials.count
            var totalScore = 0.0

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

                guard score.value.isFinite else {
                    throw AgentInferenceRealizationSearchError.invalidScore(
                        objective: objective.identifier,
                        candidate: candidate.identifier,
                        exampleIndex: exampleIndex
                    )
                }

                totalScore += score.value

                trials.append(
                    AgentInferenceOptimizationTrial(
                        candidate: candidate.identifier,
                        exampleIndex: exampleIndex,
                        score: score,
                        execution: execution.record
                    )
                )
            }

            let meanScore = totalScore / Double(examples.count)
            let trialIndexes = Array(
                firstTrialIndex..<trials.count
            )

            candidateResults.append(
                AgentInferenceOptimizationCandidateResult(
                    candidate: candidate,
                    meanScore: meanScore,
                    trialIndexes: trialIndexes
                )
            )

            if let currentSelectedMeanScore = selectedMeanScore {
                if meanScore > currentSelectedMeanScore {
                    selectedCandidate = candidate
                    selectedMeanScore = meanScore
                }
            } else {
                selectedCandidate = candidate
                selectedMeanScore = meanScore
            }
        }

        guard let selectedCandidate else {
            throw AgentInferenceRealizationSearchError.noSelectionProduced
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
