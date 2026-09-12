import AgenticInference
import AgenticPrograms

public struct ProgramCoordinateOptimizer<Program: AgentProgram>:
    Sendable
{
    private let search: ProgramRealizationSearch<Program>
    private let objectiveID: ProgramOptimization.ObjectiveID

    public init(
        program: Program,
        inferenceExecutor: any AgentInferenceExecuting,
        objective: any ProgramOptimization.Objective
    ) {
        self.search = ProgramRealizationSearch(
            program: program,
            inferenceExecutor: inferenceExecutor,
            objective: objective
        )
        self.objectiveID = objective.id
    }

    public func optimize(
        examples: [ProgramOptimization.Example<Program>],
        seed: AgentProgramRealization<Program>,
        sites: [ProgramOptimization.SiteCandidates],
        maximumPasses: Int = 4
    ) async throws -> ProgramOptimization.CoordinateResult<Program> {
        let parsedExamples = try ProgramOptimization
            .Examples<Program>
            .parse(
                examples
            )
        let searchSpace = try ProgramOptimization
            .SearchSpace<Program>
            .parse(
                seed: seed,
                sites: sites
            )
        let passLimit = try ProgramOptimization
            .CoordinatePassLimit
            .parse(
                maximumPasses
            )

        return try await optimize(
            examples: parsedExamples,
            searchSpace: searchSpace,
            passLimit: passLimit
        )
    }

    public func optimize(
        examples: ProgramOptimization.Examples<Program>,
        searchSpace: ProgramOptimization.SearchSpace<Program>,
        passLimit: ProgramOptimization.CoordinatePassLimit = .standard
    ) async throws -> ProgramOptimization.CoordinateResult<Program> {
        var current = ProgramOptimization.Candidate(
            id: ProgramOptimization.CandidateID(
                rawValue: "coordinate_seed"
            ),
            realization: searchSpace.seed,
            metadata: [
                "coordinate.source": "seed",
            ]
        )

        let initialProblem = ProgramOptimization.Problem(
            examples: examples,
            candidates: try ProgramOptimization
                .Candidates<Program>
                .parse(
                    [
                        current,
                    ]
                )
        )
        let initialResult = try await search.optimize(
            problem: initialProblem
        )
        var currentScore = initialResult.candidates[0].mean
        var decisions: [ProgramOptimization.CoordinateDecision] = []
        var trials = initialResult.trials
        var passesCompleted = 0
        var converged = false

        for pass in 1...passLimit.value {
            passesCompleted = pass
            var improvedInPass = false

            for (siteIndex, site) in searchSpace.sites.enumerated() {
                let candidates = coordinateCandidates(
                    current: current,
                    seed: searchSpace.seed,
                    site: site,
                    pass: pass,
                    siteIndex: siteIndex
                )
                let problem = ProgramOptimization.Problem(
                    examples: examples,
                    candidates: try ProgramOptimization
                        .Candidates<Program>
                        .parse(
                            candidates
                        )
                )
                let result = try await search.optimize(
                    problem: problem
                )

                var bestIndex = 0

                for index in result.candidates.indices.dropFirst() {
                    if result.candidates[index].mean.value
                        > result.candidates[bestIndex].mean.value
                    {
                        bestIndex = index
                    }
                }

                let before = currentScore
                let best = result.candidates[bestIndex]
                let accepted = best.mean.value > currentScore.value
                let firstTrialIndex = trials.count

                trials.append(
                    contentsOf: result.trials
                )

                let decisionSelection: ProgramOptimization.SiteSelection?

                if accepted {
                    let selectedInferenceCandidate =
                        site.candidates[
                            bestIndex
                        ]

                    decisionSelection = ProgramOptimization.SiteSelection(
                        site: site.site,
                        inference: site.inference,
                        candidate: selectedInferenceCandidate
                    )
                    current = best.candidate
                    currentScore = best.mean
                    improvedInPass = true
                } else {
                    decisionSelection = nil
                }

                decisions.append(
                    ProgramOptimization.CoordinateDecision(
                        pass: pass,
                        siteIndex: siteIndex,
                        site: site.site,
                        before: before,
                        after: currentScore,
                        selection: decisionSelection,
                        trialIndexes: Array(
                            firstTrialIndex..<trials.count
                        )
                    )
                )
            }

            if !improvedInPass {
                converged = true
                break
            }
        }

        return ProgramOptimization.CoordinateResult(
            objective: objectiveID,
            selected: current,
            score: currentScore,
            passesCompleted: passesCompleted,
            decisions: decisions,
            trials: trials,
            converged: converged
        )
    }

    private func coordinateCandidates(
        current: ProgramOptimization.Candidate<Program>,
        seed: AgentProgramRealization<Program>,
        site: ProgramOptimization.ResolvedSite,
        pass: Int,
        siteIndex: Int
    ) -> [ProgramOptimization.Candidate<Program>] {
        let siteNumber = siteIndex + 1
        var candidates: [ProgramOptimization.Candidate<Program>] = []

        for (candidateIndex, inferenceCandidate) in
            site.candidates.enumerated()
        {
            let candidateNumber = candidateIndex + 1
            let candidateID = ProgramOptimization.CandidateID(
                rawValue: "coordinate_p\(pass)_s\(siteNumber)_c\(candidateNumber)"
            )
            var realization = current.realization

            realization.id = AgentProgramRealizationIdentifier(
                rawValue: "\(seed.id.rawValue).\(candidateID.rawValue)"
            )
            realization.inferences.set(
                AgentInferenceRealizationBinding(
                    site: site.site,
                    inference: site.inference,
                    realization: inferenceCandidate.realization
                )
            )

            let selection = ProgramOptimization.SiteSelection(
                site: site.site,
                inference: site.inference,
                candidate: inferenceCandidate
            )
            var selections = current.selections

            if let selectionIndex = selections.firstIndex(
                where: {
                    $0.site == site.site
                }
            ) {
                selections[selectionIndex] = selection
            } else {
                selections.append(
                    selection
                )
            }

            var metadata = current.metadata
            metadata["coordinate.pass"] = String(
                pass
            )
            metadata["coordinate.site"] = site.site.rawValue
            metadata["coordinate.source_candidate"] =
                inferenceCandidate.identifier.rawValue

            candidates.append(
                ProgramOptimization.Candidate(
                    id: candidateID,
                    realization: realization,
                    selections: selections,
                    metadata: metadata
                )
            )
        }

        return candidates
    }
}
