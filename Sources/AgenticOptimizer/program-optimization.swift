import Foundation
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
        public let bindingIndex: Int
        public let candidates: [AgentInferenceRealizationCandidate]

        init(
            site: AgentInferenceSiteIdentifier,
            inference: AgentInferenceIdentifier,
            bindingIndex: Int,
            candidates: [AgentInferenceRealizationCandidate]
        ) {
            self.site = site
            self.inference = inference
            self.bindingIndex = bindingIndex
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

                guard let bindingIndex = seed.inferences.firstIndex(
                    where: {
                        $0.site == site.site
                    }
                ) else {
                    throw SearchSpaceError.seedBindingUnavailable(
                        site.site
                    )
                }

                let binding = seed.inferences[bindingIndex]

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
                        bindingIndex: bindingIndex,
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

        private init(
            _ value: Int
        ) {
            self.value = value
        }

        public static let standard = Self(
            64
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
                value
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
