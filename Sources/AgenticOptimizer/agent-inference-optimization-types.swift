import AgenticInference

public struct AgentInferenceRealizationCandidateIdentifier:
    Sendable,
    Codable,
    Hashable,
    RawRepresentable,
    ExpressibleByStringLiteral,
    CustomStringConvertible
{
    public let rawValue: String

    public init(
        rawValue: String
    ) {
        self.rawValue = rawValue
    }

    public init(
        _ rawValue: String
    ) {
        self.rawValue = rawValue
    }

    public init(
        stringLiteral value: String
    ) {
        self.rawValue = value
    }

    public var description: String {
        rawValue
    }
}

public struct AgentInferenceOptimizationObjectiveIdentifier:
    Sendable,
    Codable,
    Hashable,
    RawRepresentable,
    ExpressibleByStringLiteral,
    CustomStringConvertible
{
    public let rawValue: String

    public init(
        rawValue: String
    ) {
        self.rawValue = rawValue
    }

    public init(
        _ rawValue: String
    ) {
        self.rawValue = rawValue
    }

    public init(
        stringLiteral value: String
    ) {
        self.rawValue = value
    }

    public var description: String {
        rawValue
    }
}

public struct AgentInferenceOptimizationExample<Inference: AgentInference>:
    Sendable
{
    public var input: Inference.Input
    public var expectedOutput: Inference.Output
    public var metadata: [String: String]

    public init(
        input: Inference.Input,
        expectedOutput: Inference.Output,
        metadata: [String: String] = [:]
    ) {
        self.input = input
        self.expectedOutput = expectedOutput
        self.metadata = metadata
    }
}

public enum AgentInferenceRealizationCandidateSource:
    String,
    Sendable,
    Codable,
    Hashable
{
    case supplied
    case seed
    case instruction_variant
    case inference_proposal
}

public struct AgentInferenceRealizationCandidate:
    Sendable,
    Codable,
    Hashable
{
    public var identifier: AgentInferenceRealizationCandidateIdentifier
    public var realization: AgentInferenceRealization
    public var source: AgentInferenceRealizationCandidateSource
    public var generation: AgentInferenceExecutionRecord?
    public var metadata: [String: String]

    public init(
        identifier: AgentInferenceRealizationCandidateIdentifier,
        realization: AgentInferenceRealization,
        source: AgentInferenceRealizationCandidateSource = .supplied,
        generation: AgentInferenceExecutionRecord? = nil,
        metadata: [String: String] = [:]
    ) {
        self.identifier = identifier
        self.realization = realization
        self.source = source
        self.generation = generation
        self.metadata = metadata
    }
}

public struct AgentInferenceOptimizationScore:
    Sendable,
    Codable,
    Hashable
{
    /// Objective value. Higher values are better.
    public var value: Double
    public var metadata: [String: String]

    public init(
        value: Double,
        metadata: [String: String] = [:]
    ) {
        self.value = value
        self.metadata = metadata
    }
}

public protocol AgentInferenceOptimizationObjective: Sendable {
    var identifier: AgentInferenceOptimizationObjectiveIdentifier { get }

    func score<Inference: AgentInference>(
        _ inference: Inference.Type,
        example: AgentInferenceOptimizationExample<Inference>,
        result: AgentInferenceExecutionResult<Inference.Output>
    ) async throws -> AgentInferenceOptimizationScore
}

public struct AgentInferenceOptimizationTrial:
    Sendable,
    Codable,
    Hashable
{
    public var candidate: AgentInferenceRealizationCandidateIdentifier
    public var exampleIndex: Int
    public var score: AgentInferenceOptimizationScore
    public var execution: AgentInferenceExecutionRecord

    public init(
        candidate: AgentInferenceRealizationCandidateIdentifier,
        exampleIndex: Int,
        score: AgentInferenceOptimizationScore,
        execution: AgentInferenceExecutionRecord
    ) {
        self.candidate = candidate
        self.exampleIndex = exampleIndex
        self.score = score
        self.execution = execution
    }
}

public struct AgentInferenceOptimizationCandidateResult:
    Sendable,
    Codable,
    Hashable
{
    public var candidate: AgentInferenceRealizationCandidate
    public var meanScore: Double
    public var trialIndexes: [Int]

    public init(
        candidate: AgentInferenceRealizationCandidate,
        meanScore: Double,
        trialIndexes: [Int]
    ) {
        self.candidate = candidate
        self.meanScore = meanScore
        self.trialIndexes = trialIndexes
    }
}

public struct AgentInferenceOptimizationResult:
    Sendable,
    Codable,
    Hashable
{
    public var inference: AgentInferenceIdentifier
    public var objective: AgentInferenceOptimizationObjectiveIdentifier
    public var selectedCandidate: AgentInferenceRealizationCandidate
    public var candidates: [AgentInferenceOptimizationCandidateResult]
    public var trials: [AgentInferenceOptimizationTrial]

    public init(
        inference: AgentInferenceIdentifier,
        objective: AgentInferenceOptimizationObjectiveIdentifier,
        selectedCandidate: AgentInferenceRealizationCandidate,
        candidates: [AgentInferenceOptimizationCandidateResult],
        trials: [AgentInferenceOptimizationTrial]
    ) {
        self.inference = inference
        self.objective = objective
        self.selectedCandidate = selectedCandidate
        self.candidates = candidates
        self.trials = trials
    }
}
