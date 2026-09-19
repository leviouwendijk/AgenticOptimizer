import Agentic
import AgenticInference
import Foundation
import Primitives

public struct InferenceRealizationCandidateIdentifier:
    StringIdentifier
{
    public let rawValue: String

    public init(
        rawValue: String
    ) {
        self.rawValue = rawValue
    }
}

public struct InferenceOptimizationObjectiveIdentifier:
    StringIdentifier
{
    public let rawValue: String

    public init(
        rawValue: String
    ) {
        self.rawValue = rawValue
    }
}

public struct InferenceOptimizationExample<InferenceType: Inference>:
    Sendable
{
    public var input: InferenceType.Input
    public var expectedOutput: InferenceType.Output
    public var metadata: [String: String]

    public init(
        input: InferenceType.Input,
        expectedOutput: InferenceType.Output,
        metadata: [String: String] = [:]
    ) {
        self.input = input
        self.expectedOutput = expectedOutput
        self.metadata = metadata
    }
}

public enum InferenceRealizationCandidateSource:
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

public struct InferenceRealizationCandidate:
    Sendable,
    Codable,
    Hashable
{
    public var identifier: InferenceRealizationCandidateIdentifier
    public var realization: InferenceRealizationConfiguration
    public var source: InferenceRealizationCandidateSource
    public var generation: InferenceExecutionRecord?
    public var bootstrap: InferenceDemonstrationBootstrapRecord?
    public var metadata: [String: String]

    public init(
        identifier: InferenceRealizationCandidateIdentifier,
        realization: InferenceRealizationConfiguration,
        source: InferenceRealizationCandidateSource = .supplied,
        generation: InferenceExecutionRecord? = nil,
        bootstrap: InferenceDemonstrationBootstrapRecord? = nil,
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

public enum InferenceOptimizationScoreParsingError:
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

public struct InferenceOptimizationScore:
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
            throw InferenceOptimizationScoreParsingError.nonFinite(
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

public enum InferenceOptimizationProblemParsingError:
    Error,
    Sendable,
    LocalizedError
{
    case noExamples
    case noCandidates
    case duplicateCandidateIdentifier(
        InferenceRealizationCandidateIdentifier
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

public struct InferenceOptimizationExamples<InferenceType: Inference>:
    Sendable,
    RandomAccessCollection
{
    public typealias Element = InferenceOptimizationExample<InferenceType>
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
            throw InferenceOptimizationProblemParsingError.noExamples
        }

        return Self(
            parsed: examples
        )
    }

    public var values: [Element] {
        storage
    }
}

public struct InferenceRealizationCandidates:
    Sendable,
    RandomAccessCollection
{
    public typealias Element = InferenceRealizationCandidate
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
            throw InferenceOptimizationProblemParsingError.noCandidates
        }

        var identifiers: Set<
            InferenceRealizationCandidateIdentifier
        > = []

        for candidate in candidates {
            guard identifiers.insert(candidate.identifier).inserted else {
                throw InferenceOptimizationProblemParsingError
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

public struct InferenceOptimizationProblem<InferenceType: Inference>:
    Sendable
{
    public let examples: InferenceOptimizationExamples<InferenceType>
    public let candidates: InferenceRealizationCandidates

    public init(
        examples: InferenceOptimizationExamples<InferenceType>,
        candidates: InferenceRealizationCandidates
    ) {
        self.examples = examples
        self.candidates = candidates
    }

    public static func parse(
        examples: [InferenceOptimizationExample<InferenceType>],
        candidates: [InferenceRealizationCandidate]
    ) throws -> Self {
        Self(
            examples: try InferenceOptimizationExamples.parse(
                examples
            ),
            candidates: try InferenceRealizationCandidates.parse(
                candidates
            )
        )
    }
}

public protocol InferenceOptimizationObjective: Sendable {
    var identifier: InferenceOptimizationObjectiveIdentifier { get }

    func score<InferenceType: Inference>(
        _ inference: InferenceType.Type,
        example: InferenceOptimizationExample<InferenceType>,
        result: InferenceExecutionResult<InferenceType.Output>
    ) async throws -> InferenceOptimizationScore
}

public struct InferenceOptimizationTrial:
    Sendable,
    Codable,
    Hashable
{
    public var candidate: InferenceRealizationCandidateIdentifier
    public var exampleIndex: Int
    public var score: InferenceOptimizationScore
    public var execution: InferenceExecutionRecord
    public var durationSeconds: Double

    public init(
        candidate: InferenceRealizationCandidateIdentifier,
        exampleIndex: Int,
        score: InferenceOptimizationScore,
        execution: InferenceExecutionRecord,
        durationSeconds: Double = 0
    ) {
        self.candidate = candidate
        self.exampleIndex = exampleIndex
        self.score = score
        self.execution = execution
        self.durationSeconds = durationSeconds
    }
}

public struct InferenceOptimizationCandidateResult:
    Sendable,
    Codable,
    Hashable
{
    public var candidate: InferenceRealizationCandidate
    public let mean: InferenceOptimizationScore
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
        candidate: InferenceRealizationCandidate,
        mean: InferenceOptimizationScore,
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
                InferenceRealizationCandidate.self,
                forKey: .candidate
            ),
            mean: try InferenceOptimizationScore.parse(
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

public struct InferenceOptimizationResult:
    Sendable,
    Codable,
    Hashable
{
    public var inference: InferenceIdentifier
    public var objective: InferenceOptimizationObjectiveIdentifier
    public var selectedCandidate: InferenceRealizationCandidate
    public var candidates: [InferenceOptimizationCandidateResult]
    public var trials: [InferenceOptimizationTrial]

    public init(
        inference: InferenceIdentifier,
        objective: InferenceOptimizationObjectiveIdentifier,
        selectedCandidate: InferenceRealizationCandidate,
        candidates: [InferenceOptimizationCandidateResult],
        trials: [InferenceOptimizationTrial]
    ) {
        self.inference = inference
        self.objective = objective
        self.selectedCandidate = selectedCandidate
        self.candidates = candidates
        self.trials = trials
    }
}