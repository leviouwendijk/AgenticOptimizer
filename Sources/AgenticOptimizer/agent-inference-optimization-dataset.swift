import AgenticInference

public enum AgentInferenceOptimizationDatasetParsingError:
    Error,
    Sendable
{
    case noTrainingExamples
    case noEvaluationExamples
}

public struct AgentInferenceOptimizationDataset<Inference: AgentInference>:
    Sendable
{
    public let training: AgentInferenceOptimizationExamples<Inference>
    public let evaluation: AgentInferenceOptimizationExamples<Inference>

    public init(
        training: AgentInferenceOptimizationExamples<Inference>,
        evaluation: AgentInferenceOptimizationExamples<Inference>
    ) {
        self.training = training
        self.evaluation = evaluation
    }

    public static func parse(
        training: [AgentInferenceOptimizationExample<Inference>],
        evaluation: [AgentInferenceOptimizationExample<Inference>]
    ) throws -> Self {
        guard !training.isEmpty else {
            throw AgentInferenceOptimizationDatasetParsingError
                .noTrainingExamples
        }

        guard !evaluation.isEmpty else {
            throw AgentInferenceOptimizationDatasetParsingError
                .noEvaluationExamples
        }

        return Self(
            training: try AgentInferenceOptimizationExamples.parse(
                training
            ),
            evaluation: try AgentInferenceOptimizationExamples.parse(
                evaluation
            )
        )
    }
}

public struct AgentInferenceOptimizationEvaluation:
    Sendable,
    Codable,
    Hashable
{
    public var candidate: AgentInferenceRealizationCandidate
    public var mean: AgentInferenceOptimizationScore
    public var trials: [AgentInferenceOptimizationTrial]

    public init(
        candidate: AgentInferenceRealizationCandidate,
        mean: AgentInferenceOptimizationScore,
        trials: [AgentInferenceOptimizationTrial]
    ) {
        self.candidate = candidate
        self.mean = mean
        self.trials = trials
    }
}

public struct AgentInferenceOptimizationReport:
    Sendable,
    Codable,
    Hashable
{
    public var optimization: AgentInferenceOptimizationResult
    public var evaluation: AgentInferenceOptimizationEvaluation

    public init(
        optimization: AgentInferenceOptimizationResult,
        evaluation: AgentInferenceOptimizationEvaluation
    ) {
        self.optimization = optimization
        self.evaluation = evaluation
    }
}
