import Agentic
import AgenticPrograms

public extension ProgramOptimization {
    enum DatasetParsingError:
        Error,
        Sendable
    {
        case noTrainingExamples
        case noEvaluationExamples
    }

    struct Dataset<ProgramType: Program>:
        Sendable
    {
        public let training: Examples<ProgramType>
        public let evaluation: Examples<ProgramType>

        public init(
            training: Examples<ProgramType>,
            evaluation: Examples<ProgramType>
        ) {
            self.training = training
            self.evaluation = evaluation
        }

        public static func parse(
            training: [Example<ProgramType>],
            evaluation: [Example<ProgramType>]
        ) throws -> Self {
            guard !training.isEmpty else {
                throw DatasetParsingError.noTrainingExamples
            }

            guard !evaluation.isEmpty else {
                throw DatasetParsingError.noEvaluationExamples
            }

            return Self(
                training: try Examples.parse(
                    training
                ),
                evaluation: try Examples.parse(
                    evaluation
                )
            )
        }
    }

    struct Evaluation<ProgramType: Program>:
        Sendable
    {
        public var candidate: Candidate<ProgramType>
        public var mean: InferenceOptimizationScore
        public var trials: [Trial]

        public init(
            candidate: Candidate<ProgramType>,
            mean: InferenceOptimizationScore,
            trials: [Trial]
        ) {
            self.candidate = candidate
            self.mean = mean
            self.trials = trials
        }
    }

    struct Report<ProgramType: Program>:
        Sendable
    {
        public var optimization: Result<ProgramType>
        public var evaluation: Evaluation<ProgramType>

        public init(
            optimization: Result<ProgramType>,
            evaluation: Evaluation<ProgramType>
        ) {
            self.optimization = optimization
            self.evaluation = evaluation
        }
    }

    struct CoordinateReport<ProgramType: Program>:
        Sendable
    {
        public var optimization: CoordinateResult<ProgramType>
        public var evaluation: Evaluation<ProgramType>

        public init(
            optimization: CoordinateResult<ProgramType>,
            evaluation: Evaluation<ProgramType>
        ) {
            self.optimization = optimization
            self.evaluation = evaluation
        }
    }
}