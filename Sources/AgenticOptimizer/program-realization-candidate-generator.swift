import AgenticInference
import AgenticPrograms
import Foundation

public enum ProgramRealizationCandidateGeneratorError:
    Error,
    Sendable,
    LocalizedError
{
    case invalidMaximumCandidates(Int)
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
        case .invalidMaximumCandidates(let maximum):
            return "Program candidate generation requires a positive maximum candidate count; received \(maximum)."

        case .noSites:
            return "Program candidate generation requires at least one inference site."

        case .duplicateSite(let site):
            return "Program candidate generation contains duplicate inference site '\(site.rawValue)'."

        case .emptySiteCandidates(let site):
            return "Program inference site '\(site.rawValue)' has no realization candidates."

        case .duplicateInferenceCandidate(
            let site,
            let candidate
        ):
            return "Program inference site '\(site.rawValue)' contains duplicate candidate '\(candidate.rawValue)'."

        case .seedBindingUnavailable(let site):
            return "Program seed realization has no inference binding at site '\(site.rawValue)'."

        case .inferenceMismatch(
            let site,
            let seed,
            let candidates
        ):
            return "Program inference site '\(site.rawValue)' is bound to '\(seed.rawValue)' in the seed realization but candidate space targets '\(candidates.rawValue)'."
        }
    }
}

public struct ProgramRealizationCandidateGenerator: Sendable {
    public var maximumCandidates: Int
    public var candidateIDPrefix: String

    public init(
        maximumCandidates: Int = 64,
        candidateIDPrefix: String = "combination"
    ) {
        self.maximumCandidates = maximumCandidates
        self.candidateIDPrefix = candidateIDPrefix
    }

    public func generate<Program: AgentProgram>(
        seed: AgentProgramRealization<Program>,
        sites: [ProgramOptimization.SiteCandidates]
    ) throws -> [ProgramOptimization.Candidate<Program>] {
        guard maximumCandidates > 0 else {
            throw ProgramRealizationCandidateGeneratorError
                .invalidMaximumCandidates(
                    maximumCandidates
                )
        }

        guard !sites.isEmpty else {
            throw ProgramRealizationCandidateGeneratorError.noSites
        }

        try validate(
            seed: seed,
            sites: sites
        )

        let candidateCounts = sites.map {
            $0.candidates.count
        }
        var indexes = Array(
            repeating: 0,
            count: sites.count
        )
        var generated: [
            ProgramOptimization.Candidate<Program>
        ] = []

        while generated.count < maximumCandidates {
            let ordinal = generated.count + 1
            let candidateID = ProgramOptimization.CandidateID(
                "\(candidateIDPrefix)_\(ordinal)"
            )

            var realization = seed
            realization.id = AgentProgramRealizationIdentifier(
                "\(seed.id.rawValue).\(candidateID.rawValue)"
            )

            var selections: [ProgramOptimization.SiteSelection] = []

            for siteIndex in sites.indices {
                let site = sites[siteIndex]
                let candidate = site.candidates[
                    indexes[siteIndex]
                ]
                let bindingIndex = realization.inferences.firstIndex {
                    $0.site == site.site
                }!

                realization.inferences[bindingIndex] =
                    AgentInferenceRealizationBinding(
                        site: site.site,
                        inference: site.inference,
                        realization: candidate.realization
                    )

                selections.append(
                    ProgramOptimization.SiteSelection(
                        site: site.site,
                        inference: site.inference,
                        candidate: candidate
                    )
                )
            }

            generated.append(
                ProgramOptimization.Candidate(
                    id: candidateID,
                    realization: realization,
                    selections: selections,
                    metadata: [
                        "combination.index": String(
                            ordinal - 1
                        ),
                        "combination.site_count": String(
                            sites.count
                        ),
                    ]
                )
            )

            guard advance(
                &indexes,
                counts: candidateCounts
            ) else {
                break
            }
        }

        return generated
    }

    private func validate<Program: AgentProgram>(
        seed: AgentProgramRealization<Program>,
        sites: [ProgramOptimization.SiteCandidates]
    ) throws {
        var seenSites: Set<AgentInferenceSiteIdentifier> = []

        for site in sites {
            guard seenSites.insert(site.site).inserted else {
                throw ProgramRealizationCandidateGeneratorError
                    .duplicateSite(
                        site.site
                    )
            }

            guard !site.candidates.isEmpty else {
                throw ProgramRealizationCandidateGeneratorError
                    .emptySiteCandidates(
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
                    throw ProgramRealizationCandidateGeneratorError
                        .duplicateInferenceCandidate(
                            site: site.site,
                            candidate: candidate.identifier
                        )
                }
            }

            guard let binding = seed.inference(
                at: site.site
            ) else {
                throw ProgramRealizationCandidateGeneratorError
                    .seedBindingUnavailable(
                        site.site
                    )
            }

            guard binding.inference == site.inference else {
                throw ProgramRealizationCandidateGeneratorError
                    .inferenceMismatch(
                        site: site.site,
                        seed: binding.inference,
                        candidates: site.inference
                    )
            }
        }
    }

    private func advance(
        _ indexes: inout [Int],
        counts: [Int]
    ) -> Bool {
        for index in indexes.indices.reversed() {
            indexes[index] += 1

            if indexes[index] < counts[index] {
                return true
            }

            indexes[index] = 0
        }

        return false
    }
}
