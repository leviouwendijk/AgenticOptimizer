import Agentic
import AgenticInference
import AgenticPrograms

public struct ProgramCoordinateOptimizer<ProgramType: Program>:
    Sendable
{
    private let search: ProgramRealizationSearch<ProgramType>
    private let objectiveID: ProgramOptimization.ObjectiveID

    public init(
        program: ProgramType,
        inferenceExecutor: any InferenceExecuting,
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
        dataset: ProgramOptimization.Dataset<ProgramType>,
        seed: ProgramRealization<ProgramType>,
        sites: [ProgramOptimization.SiteCandidates<ProgramType>],
        maximumPasses: Int = 4
    ) async throws -> ProgramOptimization.CoordinateReport<ProgramType> {
        let searchSpace = try ProgramOptimization
            .SearchSpace<ProgramType>
            .parse(
                seed: seed,
                sites: sites
            )
        let passLimit = try ProgramOptimization
            .CoordinatePassLimit
            .parse(
                maximumPasses
            )
        let optimization = try await optimize(
            examples: dataset.training,
            searchSpace: searchSpace,
            passLimit: passLimit
        )
        let evaluation = try await search.evaluate(
            candidate: optimization.selected,
            examples: dataset.evaluation
        )

        return ProgramOptimization.CoordinateReport(
            optimization: optimization,
            evaluation: evaluation
        )
    }

    public func optimize(
        examples: [ProgramOptimization.Example<ProgramType>],
        seed: ProgramRealization<ProgramType>,
        sites: [ProgramOptimization.SiteCandidates<ProgramType>],
        maximumPasses: Int = 4
    ) async throws -> ProgramOptimization.CoordinateResult<ProgramType> {
        let parsedExamples = try ProgramOptimization
            .Examples<ProgramType>
            .parse(
                examples
            )
        let searchSpace = try ProgramOptimization
            .SearchSpace<ProgramType>
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
        examples: ProgramOptimization.Examples<ProgramType>,
        searchSpace: ProgramOptimization.SearchSpace<ProgramType>,
        passLimit: ProgramOptimization.CoordinatePassLimit = .standard
    ) async throws -> ProgramOptimization.CoordinateResult<ProgramType> {
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
                .Candidates<ProgramType>
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
                    site: site,
                    pass: pass,
                    siteIndex: siteIndex
                )
                let problem = ProgramOptimization.Problem(
                    examples: examples,
                    candidates: try ProgramOptimization
                        .Candidates<ProgramType>
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
        current: ProgramOptimization.Candidate<ProgramType>,
        site: ProgramOptimization.SiteCandidates<ProgramType>,
        pass: Int,
        siteIndex: Int
    ) -> [ProgramOptimization.Candidate<ProgramType>] {
        let siteNumber = siteIndex + 1
        var candidates: [ProgramOptimization.Candidate<ProgramType>] = []

        for (candidateIndex, inferenceCandidate) in
            site.candidates.enumerated()
        {
            let candidateNumber = candidateIndex + 1
            let candidateID = ProgramOptimization.CandidateID(
                rawValue: "coordinate_p\(pass)_s\(siteNumber)_c\(candidateNumber)"
            )
            let realization = site.applying(
                inferenceCandidate,
                to: current.realization
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