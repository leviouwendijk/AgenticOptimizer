import Agentic
import AgenticInference

public enum InferenceOptimizationDatasetParsingError:
    Error,
    Sendable
{
    case noTrainingExamples
    case noEvaluationExamples
}

public struct InferenceOptimizationDataset<InferenceType: Inference>:
    Sendable
{
    public let training: InferenceOptimizationExamples<InferenceType>
    public let evaluation: InferenceOptimizationExamples<InferenceType>

    public init(
        training: InferenceOptimizationExamples<InferenceType>,
        evaluation: InferenceOptimizationExamples<InferenceType>
    ) {
        self.training = training
        self.evaluation = evaluation
    }

    public static func parse(
        training: [InferenceOptimizationExample<InferenceType>],
        evaluation: [InferenceOptimizationExample<InferenceType>]
    ) throws -> Self {
        guard !training.isEmpty else {
            throw InferenceOptimizationDatasetParsingError
                .noTrainingExamples
        }

        guard !evaluation.isEmpty else {
            throw InferenceOptimizationDatasetParsingError
                .noEvaluationExamples
        }

        return Self(
            training: try InferenceOptimizationExamples.parse(
                training
            ),
            evaluation: try InferenceOptimizationExamples.parse(
                evaluation
            )
        )
    }
}

public struct InferenceOptimizationEvaluation:
    Sendable,
    Codable,
    Hashable
{
    public var candidate: InferenceRealizationCandidate
    public var mean: InferenceOptimizationScore
    public var trials: [InferenceOptimizationTrial]

    public init(
        candidate: InferenceRealizationCandidate,
        mean: InferenceOptimizationScore,
        trials: [InferenceOptimizationTrial]
    ) {
        self.candidate = candidate
        self.mean = mean
        self.trials = trials
    }
}

public struct InferenceOptimizationReport:
    Sendable,
    Codable,
    Hashable
{
    public var optimization: InferenceOptimizationResult
    public var evaluation: InferenceOptimizationEvaluation

    public init(
        optimization: InferenceOptimizationResult,
        evaluation: InferenceOptimizationEvaluation
    ) {
        self.optimization = optimization
        self.evaluation = evaluation
    }
}