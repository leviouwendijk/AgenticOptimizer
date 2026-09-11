import AgenticPrograms

public struct ProgramRealizationCandidateGenerator: Sendable {
    public var limit: ProgramOptimization.CandidateLimit
    public var candidateIDPrefix: String

    public init(
        limit: ProgramOptimization.CandidateLimit = .standard,
        candidateIDPrefix: String = "combination"
    ) {
        self.limit = limit
        self.candidateIDPrefix = candidateIDPrefix
    }

    public func generate<Program: AgentProgram>(
        from searchSpace: ProgramOptimization.SearchSpace<Program>
    ) -> [ProgramOptimization.Candidate<Program>] {
        let sites = searchSpace.sites
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

        while generated.count < limit.value {
            let ordinal = generated.count + 1
            let candidateID = ProgramOptimization.CandidateID(
                "\(candidateIDPrefix)_\(ordinal)"
            )

            var realization = searchSpace.seed
            realization.id = AgentProgramRealizationIdentifier(
                "\(searchSpace.seed.id.rawValue).\(candidateID.rawValue)"
            )

            var selections: [ProgramOptimization.SiteSelection] = []

            for siteIndex in sites.indices {
                let site = sites[siteIndex]
                let candidate = site.candidates[
                    indexes[siteIndex]
                ]

                realization.inferences.set(
                    AgentInferenceRealizationBinding(
                        site: site.site,
                        inference: site.inference,
                        realization: candidate.realization
                    )
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
