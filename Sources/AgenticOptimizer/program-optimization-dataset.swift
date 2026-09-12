import AgenticPrograms

public extension ProgramOptimization {
    enum DatasetParsingError:
        Error,
        Sendable
    {
        case noTrainingExamples
        case noEvaluationExamples
    }

    struct Dataset<Program: AgentProgram>:
        Sendable
    {
        public let training: Examples<Program>
        public let evaluation: Examples<Program>

        public init(
            training: Examples<Program>,
            evaluation: Examples<Program>
        ) {
            self.training = training
            self.evaluation = evaluation
        }

        public static func parse(
            training: [Example<Program>],
            evaluation: [Example<Program>]
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

    struct Evaluation<Program: AgentProgram>:
        Sendable
    {
        public var candidate: Candidate<Program>
        public var mean: AgentInferenceOptimizationScore
        public var trials: [Trial]

        public init(
            candidate: Candidate<Program>,
            mean: AgentInferenceOptimizationScore,
            trials: [Trial]
        ) {
            self.candidate = candidate
            self.mean = mean
            self.trials = trials
        }
    }

    struct Report<Program: AgentProgram>:
        Sendable
    {
        public var optimization: Result<Program>
        public var evaluation: Evaluation<Program>

        public init(
            optimization: Result<Program>,
            evaluation: Evaluation<Program>
        ) {
            self.optimization = optimization
            self.evaluation = evaluation
        }
    }

    struct CoordinateReport<Program: AgentProgram>:
        Sendable
    {
        public var optimization: CoordinateResult<Program>
        public var evaluation: Evaluation<Program>

        public init(
            optimization: CoordinateResult<Program>,
            evaluation: Evaluation<Program>
        ) {
            self.optimization = optimization
            self.evaluation = evaluation
        }
    }
}
