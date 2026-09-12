import AgenticInference
import Foundation
import Primitives

public struct AgentInferenceRealizationCandidateIdentifier:
    StringIdentifier
{
    public let rawValue: String

    public init(
        rawValue: String
    ) {
        self.rawValue = rawValue
    }
}

public struct AgentInferenceOptimizationObjectiveIdentifier:
    StringIdentifier
{
    public let rawValue: String

    public init(
        rawValue: String
    ) {
        self.rawValue = rawValue
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
    case demonstration_variant
    case demonstration_bootstrap
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
    public var bootstrap: AgentInferenceDemonstrationBootstrapRecord?
    public var metadata: [String: String]

    public init(
        identifier: AgentInferenceRealizationCandidateIdentifier,
        realization: AgentInferenceRealization,
        source: AgentInferenceRealizationCandidateSource = .supplied,
        generation: AgentInferenceExecutionRecord? = nil,
        bootstrap: AgentInferenceDemonstrationBootstrapRecord? = nil,
        metadata: [String: String] = [:]
    ) {
        self.identifier = identifier
        self.realization = realization
        self.source = source
        self.generation = generation
        self.bootstrap = bootstrap
        self.metadata = metadata
    }
}

public enum AgentInferenceOptimizationScoreParsingError:
    Error,
    Sendable,
    LocalizedError
{
    case nonFinite(Double)

    public var errorDescription: String? {
        switch self {
        case .nonFinite(let value):
            return "Inference optimization score must be finite; received \(value)."
        }
    }
}

public struct AgentInferenceOptimizationScore:
    Sendable,
    Codable,
    Hashable
{
    /// Objective value. Higher values are better.
    public let value: Double
    public let metadata: [String: String]

    private enum CodingKeys: String, CodingKey {
        case value
        case metadata
    }

    private init(
        parsedValue value: Double,
        metadata: [String: String]
    ) {
        self.value = value
        self.metadata = metadata
    }

    public init(
        value: Double,
        metadata: [String: String] = [:]
    ) throws {
        self = try Self.parse(
            value: value,
            metadata: metadata
        )
    }

    public static func parse(
        value: Double,
        metadata: [String: String] = [:]
    ) throws -> Self {
        guard value.isFinite else {
            throw AgentInferenceOptimizationScoreParsingError.nonFinite(
                value
            )
        }

        return Self(
            parsedValue: value,
            metadata: metadata
        )
    }

    public init(
        from decoder: Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        self = try Self.parse(
            value: try container.decode(
                Double.self,
                forKey: .value
            ),
            metadata: try container.decodeIfPresent(
                [String: String].self,
                forKey: .metadata
            ) ?? [:]
        )
    }

    public func encode(
        to encoder: Encoder
    ) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )

        try container.encode(
            value,
            forKey: .value
        )
        try container.encode(
            metadata,
            forKey: .metadata
        )
    }
}

public enum AgentInferenceOptimizationProblemParsingError:
    Error,
    Sendable,
    LocalizedError
{
    case noExamples
    case noCandidates
    case duplicateCandidateIdentifier(
        AgentInferenceRealizationCandidateIdentifier
    )

    public var errorDescription: String? {
        switch self {
        case .noExamples:
            return "Inference realization optimization requires at least one example."

        case .noCandidates:
            return "Inference realization optimization requires at least one candidate."

        case .duplicateCandidateIdentifier(let identifier):
            return "Inference realization optimization contains duplicate candidate identifier '\(identifier.rawValue)'."
        }
    }
}

public struct AgentInferenceOptimizationExamples<Inference: AgentInference>:
    Sendable,
    RandomAccessCollection
{
    public typealias Element = AgentInferenceOptimizationExample<Inference>
    public typealias Index = Int

    private let storage: [Element]

    public var startIndex: Int {
        storage.startIndex
    }

    public var endIndex: Int {
        storage.endIndex
    }

    public subscript(
        position: Int
    ) -> Element {
        storage[position]
    }

    private init(
        parsed storage: [Element]
    ) {
        self.storage = storage
    }

    public static func parse(
        _ examples: [Element]
    ) throws -> Self {
        guard !examples.isEmpty else {
            throw AgentInferenceOptimizationProblemParsingError.noExamples
        }

        return Self(
            parsed: examples
        )
    }

    public var values: [Element] {
        storage
    }
}

public struct AgentInferenceRealizationCandidates:
    Sendable,
    RandomAccessCollection
{
    public typealias Element = AgentInferenceRealizationCandidate
    public typealias Index = Int

    private let storage: [Element]

    public var startIndex: Int {
        storage.startIndex
    }

    public var endIndex: Int {
        storage.endIndex
    }

    public subscript(
        position: Int
    ) -> Element {
        storage[position]
    }

    public var initial: Element {
        storage[0]
    }

    private init(
        parsed storage: [Element]
    ) {
        self.storage = storage
    }

    public static func parse(
        _ candidates: [Element]
    ) throws -> Self {
        guard !candidates.isEmpty else {
            throw AgentInferenceOptimizationProblemParsingError.noCandidates
        }

        var identifiers: Set<
            AgentInferenceRealizationCandidateIdentifier
        > = []

        for candidate in candidates {
            guard identifiers.insert(candidate.identifier).inserted else {
                throw AgentInferenceOptimizationProblemParsingError
                    .duplicateCandidateIdentifier(
                        candidate.identifier
                    )
            }
        }

        return Self(
            parsed: candidates
        )
    }

    public var values: [Element] {
        storage
    }
}

public struct AgentInferenceOptimizationProblem<Inference: AgentInference>:
    Sendable
{
    public let examples: AgentInferenceOptimizationExamples<Inference>
    public let candidates: AgentInferenceRealizationCandidates

    public init(
        examples: AgentInferenceOptimizationExamples<Inference>,
        candidates: AgentInferenceRealizationCandidates
    ) {
        self.examples = examples
        self.candidates = candidates
    }

    public static func parse(
        examples: [AgentInferenceOptimizationExample<Inference>],
        candidates: [AgentInferenceRealizationCandidate]
    ) throws -> Self {
        Self(
            examples: try AgentInferenceOptimizationExamples.parse(
                examples
            ),
            candidates: try AgentInferenceRealizationCandidates.parse(
                candidates
            )
        )
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
    public var durationSeconds: Double

    public init(
        candidate: AgentInferenceRealizationCandidateIdentifier,
        exampleIndex: Int,
        score: AgentInferenceOptimizationScore,
        execution: AgentInferenceExecutionRecord,
        durationSeconds: Double = 0
    ) {
        self.candidate = candidate
        self.exampleIndex = exampleIndex
        self.score = score
        self.execution = execution
        self.durationSeconds = durationSeconds
    }
}

public struct AgentInferenceOptimizationCandidateResult:
    Sendable,
    Codable,
    Hashable
{
    public var candidate: AgentInferenceRealizationCandidate
    public let mean: AgentInferenceOptimizationScore
    public var trialIndexes: [Int]

    public var meanScore: Double {
        mean.value
    }

    private enum CodingKeys: String, CodingKey {
        case candidate
        case meanScore
        case trialIndexes
    }

    public init(
        candidate: AgentInferenceRealizationCandidate,
        mean: AgentInferenceOptimizationScore,
        trialIndexes: [Int]
    ) {
        self.candidate = candidate
        self.mean = mean
        self.trialIndexes = trialIndexes
    }

    public init(
        from decoder: Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        self.init(
            candidate: try container.decode(
                AgentInferenceRealizationCandidate.self,
                forKey: .candidate
            ),
            mean: try AgentInferenceOptimizationScore.parse(
                value: try container.decode(
                    Double.self,
                    forKey: .meanScore
                )
            ),
            trialIndexes: try container.decode(
                [Int].self,
                forKey: .trialIndexes
            )
        )
    }

    public func encode(
        to encoder: Encoder
    ) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )

        try container.encode(
            candidate,
            forKey: .candidate
        )
        try container.encode(
            meanScore,
            forKey: .meanScore
        )
        try container.encode(
            trialIndexes,
            forKey: .trialIndexes
        )
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
