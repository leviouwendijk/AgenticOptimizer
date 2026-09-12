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

    struct SiteCandidates:
        Sendable,
        Codable,
        Hashable
    {
        public var site: AgentInferenceSiteIdentifier
        public var inference: AgentInferenceIdentifier
        public var candidates: [AgentInferenceRealizationCandidate]

        public init(
            site: AgentInferenceSiteIdentifier,
            inference: AgentInferenceIdentifier,
            candidates: [AgentInferenceRealizationCandidate]
        ) {
            self.site = site
            self.inference = inference
            self.candidates = candidates
        }
    }

    struct ResolvedSite: Sendable {
        public let site: AgentInferenceSiteIdentifier
        public let inference: AgentInferenceIdentifier
        public let candidates: [AgentInferenceRealizationCandidate]

        init(
            site: AgentInferenceSiteIdentifier,
            inference: AgentInferenceIdentifier,
            candidates: [AgentInferenceRealizationCandidate]
        ) {
            self.site = site
            self.inference = inference
            self.candidates = candidates
        }
    }

    enum SearchSpaceError:
        Error,
        Sendable,
        LocalizedError
    {
        case noSites
        case duplicateSite(AgentInferenceSiteIdentifier)
        case emptySiteCandidates(AgentInferenceSiteIdentifier)
        case duplicateInferenceCandidate(
            site: AgentInferenceSiteIdentifier,
            candidate: AgentInferenceRealizationCandidateIdentifier
        )
        case seedBindingUnavailable(AgentInferenceSiteIdentifier)
        case inferenceMismatch(
            site: AgentInferenceSiteIdentifier,
            seed: AgentInferenceIdentifier,
            candidates: AgentInferenceIdentifier
        )

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

            case .inferenceMismatch(
                let site,
                let seed,
                let candidates
            ):
                return "Program optimization inference site '\(site.rawValue)' is bound to '\(seed.rawValue)' in the seed realization but candidate space targets '\(candidates.rawValue)'."
            }
        }
    }

    struct SearchSpace<Program: AgentProgram>: Sendable {
        public let seed: AgentProgramRealization<Program>
        public let sites: [ResolvedSite]

        private init(
            seed: AgentProgramRealization<Program>,
            sites: [ResolvedSite]
        ) {
            self.seed = seed
            self.sites = sites
        }

        public static func parse(
            seed: AgentProgramRealization<Program>,
            sites: [SiteCandidates]
        ) throws -> Self {
            guard !sites.isEmpty else {
                throw SearchSpaceError.noSites
            }

            var seenSites: Set<AgentInferenceSiteIdentifier> = []
            var resolved: [ResolvedSite] = []

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
                    AgentInferenceRealizationCandidateIdentifier
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

                guard let binding = seed.inference(
                    at: site.site
                ) else {
                    throw SearchSpaceError.seedBindingUnavailable(
                        site.site
                    )
                }

                guard binding.inference == site.inference else {
                    throw SearchSpaceError.inferenceMismatch(
                        site: site.site,
                        seed: binding.inference,
                        candidates: site.inference
                    )
                }

                resolved.append(
                    ResolvedSite(
                        site: site.site,
                        inference: site.inference,
                        candidates: site.candidates
                    )
                )
            }

            return Self(
                seed: seed,
                sites: resolved
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
        public var site: AgentInferenceSiteIdentifier
        public var inference: AgentInferenceIdentifier
        public var candidate: AgentInferenceRealizationCandidate

        public init(
            site: AgentInferenceSiteIdentifier,
            inference: AgentInferenceIdentifier,
            candidate: AgentInferenceRealizationCandidate
        ) {
            self.site = site
            self.inference = inference
            self.candidate = candidate
        }
    }

    struct Candidate<Program: AgentProgram>: Sendable {
        public var id: CandidateID
        public var realization: AgentProgramRealization<Program>
        public var selections: [SiteSelection]
        public var metadata: [String: String]

        public init(
            id: CandidateID,
            realization: AgentProgramRealization<Program>,
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

    struct Examples<Program: AgentProgram>:
        Sendable,
        RandomAccessCollection
    {
        public typealias Element = Example<Program>
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

    struct Candidates<Program: AgentProgram>:
        Sendable,
        RandomAccessCollection
    {
        public typealias Element = Candidate<Program>
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

    struct Problem<Program: AgentProgram>: Sendable {
        public let examples: Examples<Program>
        public let candidates: Candidates<Program>

        public init(
            examples: Examples<Program>,
            candidates: Candidates<Program>
        ) {
            self.examples = examples
            self.candidates = candidates
        }

        public static func parse(
            examples: [Example<Program>],
            candidates: [Candidate<Program>]
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
        public var score: AgentInferenceOptimizationScore
        public var executions: [AgentInferenceExecutionRecord]
        public var durationSeconds: Double

        public init(
            candidate: CandidateID,
            exampleIndex: Int,
            score: AgentInferenceOptimizationScore,
            executions: [AgentInferenceExecutionRecord] = [],
            durationSeconds: Double = 0
        ) {
            self.candidate = candidate
            self.exampleIndex = exampleIndex
            self.score = score
            self.executions = executions
            self.durationSeconds = durationSeconds
        }
    }

    struct CandidateResult<Program: AgentProgram>: Sendable {
        public var candidate: Candidate<Program>
        public let mean: AgentInferenceOptimizationScore
        public var trialIndexes: [Int]

        public var meanScore: Double {
            mean.value
        }

        public init(
            candidate: Candidate<Program>,
            mean: AgentInferenceOptimizationScore,
            trialIndexes: [Int]
        ) {
            self.candidate = candidate
            self.mean = mean
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
