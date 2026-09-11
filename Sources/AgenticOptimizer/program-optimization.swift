import AgenticInference
import AgenticPrograms
import Primitives

public enum ProgramOptimization {}

public extension ProgramOptimization {
    struct CandidateID:
        StringIdentifier
    {
        public let rawValue: String

        public init(
            rawValue: String
        ) {
            self.rawValue = rawValue
        }
    }

    struct ObjectiveID:
        StringIdentifier
    {
        public let rawValue: String

        public init(
            rawValue: String
        ) {
            self.rawValue = rawValue
        }
    }

    struct Example<Program: AgentProgram>: Sendable {
        public var input: Program.Input
        public var expectedOutput: Program.Output
        public var metadata: [String: String]

        public init(
            input: Program.Input,
            expectedOutput: Program.Output,
            metadata: [String: String] = [:]
        ) {
            self.input = input
            self.expectedOutput = expectedOutput
            self.metadata = metadata
        }
    }

    struct Candidate<Program: AgentProgram>: Sendable {
        public var id: CandidateID
        public var realization: AgentProgramRealization<Program>
        public var metadata: [String: String]

        public init(
            id: CandidateID,
            realization: AgentProgramRealization<Program>,
            metadata: [String: String] = [:]
        ) {
            self.id = id
            self.realization = realization
            self.metadata = metadata
        }
    }

    struct Trial:
        Sendable,
        Codable,
        Hashable
    {
        public var candidate: CandidateID
        public var exampleIndex: Int
        public var score: AgentInferenceOptimizationScore

        public init(
            candidate: CandidateID,
            exampleIndex: Int,
            score: AgentInferenceOptimizationScore
        ) {
            self.candidate = candidate
            self.exampleIndex = exampleIndex
            self.score = score
        }
    }

    struct CandidateResult<Program: AgentProgram>: Sendable {
        public var candidate: Candidate<Program>
        public var meanScore: Double
        public var trialIndexes: [Int]

        public init(
            candidate: Candidate<Program>,
            meanScore: Double,
            trialIndexes: [Int]
        ) {
            self.candidate = candidate
            self.meanScore = meanScore
            self.trialIndexes = trialIndexes
        }
    }

    struct Result<Program: AgentProgram>: Sendable {
        public var objective: ObjectiveID
        public var selected: Candidate<Program>
        public var candidates: [CandidateResult<Program>]
        public var trials: [Trial]

        public init(
            objective: ObjectiveID,
            selected: Candidate<Program>,
            candidates: [CandidateResult<Program>],
            trials: [Trial]
        ) {
            self.objective = objective
            self.selected = selected
            self.candidates = candidates
            self.trials = trials
        }
    }

    protocol Objective: Sendable {
        var id: ObjectiveID { get }

        func score<Program: AgentProgram>(
            _ program: Program.Type,
            example: Example<Program>,
            output: Program.Output
        ) async throws -> AgentInferenceOptimizationScore
    }
}
