import Agentic
import AgenticInference
import AgenticPrograms
import Foundation
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

    struct Example<ProgramType: Program>: Sendable {
        public var input: ProgramType.Input
        public var expectedOutput: ProgramType.Output
        public var metadata: [String: String]

        public init(
            input: ProgramType.Input,
            expectedOutput: ProgramType.Output,
            metadata: [String: String] = [:]
        ) {
            self.input = input
            self.expectedOutput = expectedOutput
            self.metadata = metadata
        }
    }

    struct SiteCandidates<ProgramType: Program>: Sendable {
        public let site: InferenceSiteIdentifier
        public let inference: InferenceIdentifier
        public let candidates: [InferenceRealizationCandidate]

        private let seedConfiguration:
            @Sendable (
                ProgramRealization<ProgramType>
            ) -> InferenceRealizationConfiguration?

        private let applyCandidate:
            @Sendable (
                InferenceRealizationCandidate,
                ProgramRealization<ProgramType>
            ) -> ProgramRealization<ProgramType>

        public init<InferenceType: Inference>(
            _ site: InferenceSite<
                ProgramType,
                InferenceType
            >,
            candidates: [InferenceRealizationCandidate]
        ) {
            self.site = site.identifier
            self.inference = site.inference
            self.candidates = candidates
            self.seedConfiguration = { realization in
                guard
                    let binding = realization.binding(
                        for: site
                    ),
                    binding.inference == site.inference
                else {
                    return nil
                }

                return binding.configuration
            }
            self.applyCandidate = { candidate, realization in
                realization.replacing(
                    site,
                    with: InferenceRealizationDefinition<InferenceType>(
                        identifier: InferenceRealizationIdentifier(
                            rawValue: candidate.identifier.rawValue
                        ),
                        configuration: candidate.realization
                    )
                )
            }
        }

        func seedConfiguration(
            in realization: ProgramRealization<ProgramType>
        ) -> InferenceRealizationConfiguration? {
            seedConfiguration(
                realization
            )
        }

        func applying(
            _ candidate: InferenceRealizationCandidate,
            to realization: ProgramRealization<ProgramType>
        ) -> ProgramRealization<ProgramType> {
            applyCandidate(
                candidate,
                realization
            )
        }
    }

    enum SearchSpaceError:
        Error,
        Sendable,
        LocalizedError
    {
        case noSites
        case duplicateSite(InferenceSiteIdentifier)
        case emptySiteCandidates(InferenceSiteIdentifier)
        case duplicateInferenceCandidate(
            site: InferenceSiteIdentifier,
            candidate: InferenceRealizationCandidateIdentifier
        )
        case seedBindingUnavailable(InferenceSiteIdentifier)

        public var errorDescription: String? {
            switch self {
            case .noSites:
                return "Program optimization search space requires at least one inference site."

            case .duplicateSite(let site):
                return "Program optimization search space contains duplicate inference site '\(site.rawValue)'."

            case .emptySiteCandidates(let site):
                return "Program optimization inference site '\(site.rawValue)' has no realization candidates."

            case .duplicateInferenceCandidate(
                let site,
                let candidate
            ):
                return "Program optimization inference site '\(site.rawValue)' contains duplicate candidate '\(candidate.rawValue)'."

            case .seedBindingUnavailable(let site):
                return "Program optimization seed realization has no inference binding at site '\(site.rawValue)'."
            }
        }
    }

    struct SearchSpace<ProgramType: Program>: Sendable {
        public let seed: ProgramRealization<ProgramType>
        public let sites: [SiteCandidates<ProgramType>]

        private init(
            seed: ProgramRealization<ProgramType>,
            sites: [SiteCandidates<ProgramType>]
        ) {
            self.seed = seed
            self.sites = sites
        }

        public static func parse(
            seed: ProgramRealization<ProgramType>,
            sites: [SiteCandidates<ProgramType>]
        ) throws -> Self {
            guard !sites.isEmpty else {
                throw SearchSpaceError.noSites
            }

            var seenSites: Set<InferenceSiteIdentifier> = []

            for site in sites {
                guard seenSites.insert(site.site).inserted else {
                    throw SearchSpaceError.duplicateSite(
                        site.site
                    )
                }

                guard !site.candidates.isEmpty else {
                    throw SearchSpaceError.emptySiteCandidates(
                        site.site
                    )
                }

                var seenCandidates: Set<
                    InferenceRealizationCandidateIdentifier
                > = []

                for candidate in site.candidates {
                    guard
                        seenCandidates
                            .insert(candidate.identifier)
                            .inserted
                    else {
                        throw SearchSpaceError
                            .duplicateInferenceCandidate(
                                site: site.site,
                                candidate: candidate.identifier
                            )
                    }
                }

                guard
                    site.seedConfiguration(
                        in: seed
                    ) != nil
                else {
                    throw SearchSpaceError.seedBindingUnavailable(
                        site.site
                    )
                }
            }

            return Self(
                seed: seed,
                sites: sites
            )
        }
    }

    enum CandidateLimitError:
        Error,
        Sendable,
        LocalizedError
    {
        case nonPositive(Int)

        public var errorDescription: String? {
            switch self {
            case .nonPositive(let value):
                return "Program optimization candidate limit must be positive; received \(value)."
            }
        }
    }

    struct CandidateLimit:
        Sendable,
        Codable,
        Hashable
    {
        public let value: Int

        private enum CodingKeys: String, CodingKey {
            case value
        }

        private init(
            parsed value: Int
        ) {
            self.value = value
        }

        public static let standard = Self(
            parsed: 64
        )

        public static func parse(
            _ value: Int
        ) throws -> Self {
            guard value > 0 else {
                throw CandidateLimitError.nonPositive(
                    value
                )
            }

            return Self(
                parsed: value
            )
        }

        public init(
            from decoder: Decoder
        ) throws {
            let container = try decoder.container(
                keyedBy: CodingKeys.self
            )
            self = try Self.parse(
                try container.decode(
                    Int.self,
                    forKey: .value
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
                value,
                forKey: .value
            )
        }
    }

    struct SiteSelection:
        Sendable,
        Codable,
        Hashable
    {
        public var site: InferenceSiteIdentifier
        public var inference: InferenceIdentifier
        public var candidate: InferenceRealizationCandidate

        public init(
            site: InferenceSiteIdentifier,
            inference: InferenceIdentifier,
            candidate: InferenceRealizationCandidate
        ) {
            self.site = site
            self.inference = inference
            self.candidate = candidate
        }
    }

    struct Candidate<ProgramType: Program>: Sendable {
        public var id: CandidateID
        public var realization: ProgramRealization<ProgramType>
        public var selections: [SiteSelection]
        public var metadata: [String: String]

        public init(
            id: CandidateID,
            realization: ProgramRealization<ProgramType>,
            selections: [SiteSelection] = [],
            metadata: [String: String] = [:]
        ) {
            self.id = id
            self.realization = realization
            self.selections = selections
            self.metadata = metadata
        }
    }

    enum ProblemParsingError:
        Error,
        Sendable,
        LocalizedError
    {
        case noExamples
        case noCandidates
        case duplicateCandidateIdentifier(CandidateID)

        public var errorDescription: String? {
            switch self {
            case .noExamples:
                return "Program realization optimization requires at least one example."

            case .noCandidates:
                return "Program realization optimization requires at least one candidate."

            case .duplicateCandidateIdentifier(let identifier):
                return "Program realization optimization contains duplicate candidate identifier '\(identifier.rawValue)'."
            }
        }
    }

    struct Examples<ProgramType: Program>:
        Sendable,
        RandomAccessCollection
    {
        public typealias Element = Example<ProgramType>
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
                throw ProblemParsingError.noExamples
            }

            return Self(
                parsed: examples
            )
        }

        public var values: [Element] {
            storage
        }
    }

    struct Candidates<ProgramType: Program>:
        Sendable,
        RandomAccessCollection
    {
        public typealias Element = Candidate<ProgramType>
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
                throw ProblemParsingError.noCandidates
            }

            var identifiers: Set<CandidateID> = []

            for candidate in candidates {
                guard identifiers.insert(candidate.id).inserted else {
                    throw ProblemParsingError
                        .duplicateCandidateIdentifier(
                            candidate.id
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

    struct Problem<ProgramType: Program>: Sendable {
        public let examples: Examples<ProgramType>
        public let candidates: Candidates<ProgramType>

        public init(
            examples: Examples<ProgramType>,
            candidates: Candidates<ProgramType>
        ) {
            self.examples = examples
            self.candidates = candidates
        }

        public static func parse(
            examples: [Example<ProgramType>],
            candidates: [Candidate<ProgramType>]
        ) throws -> Self {
            Self(
                examples: try Examples.parse(
                    examples
                ),
                candidates: try Candidates.parse(
                    candidates
                )
            )
        }
    }

    struct Trial:
        Sendable,
        Codable,
        Hashable
    {
        public var candidate: CandidateID
        public var exampleIndex: Int
        public var score: InferenceOptimizationScore
        public var executions: [InferenceExecutionRecord]
        public var durationSeconds: Double

        public init(
            candidate: CandidateID,
            exampleIndex: Int,
            score: InferenceOptimizationScore,
            executions: [InferenceExecutionRecord] = [],
            durationSeconds: Double = 0
        ) {
            self.candidate = candidate
            self.exampleIndex = exampleIndex
            self.score = score
            self.executions = executions
            self.durationSeconds = durationSeconds
        }
    }

    struct CandidateResult<ProgramType: Program>: Sendable {
        public var candidate: Candidate<ProgramType>
        public let mean: InferenceOptimizationScore
        public var trialIndexes: [Int]

        public var meanScore: Double {
            mean.value
        }

        public init(
            candidate: Candidate<ProgramType>,
            mean: InferenceOptimizationScore,
            trialIndexes: [Int]
        ) {
            self.candidate = candidate
            self.mean = mean
            self.trialIndexes = trialIndexes
        }
    }

    struct Result<ProgramType: Program>: Sendable {
        public var objective: ObjectiveID
        public var selected: Candidate<ProgramType>
        public var candidates: [CandidateResult<ProgramType>]
        public var trials: [Trial]

        public init(
            objective: ObjectiveID,
            selected: Candidate<ProgramType>,
            candidates: [CandidateResult<ProgramType>],
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

        func score<ProgramType: Program>(
            _ program: ProgramType.Type,
            example: Example<ProgramType>,
            output: ProgramType.Output
        ) async throws -> InferenceOptimizationScore
    }
}
