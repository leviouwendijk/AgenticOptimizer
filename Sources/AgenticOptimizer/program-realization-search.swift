import AgenticInference
import AgenticPrograms

public struct ProgramRealizationSearch<Program: AgentProgram>: Sendable {
    private let program: Program
    private let inferenceExecutor: any AgentInferenceExecuting
    private let objective: any ProgramOptimization.Objective

    public init(
        program: Program,
        inferenceExecutor: any AgentInferenceExecuting,
        objective: any ProgramOptimization.Objective
    ) {
        self.program = program
        self.inferenceExecutor = inferenceExecutor
        self.objective = objective
    }

    public func optimize(
        examples: [ProgramOptimization.Example<Program>],
        seed: AgentProgramRealization<Program>,
        sites: [ProgramOptimization.SiteCandidates],
        maximumCandidates: Int = 64,
        candidateIDPrefix: String = "combination"
    ) async throws -> ProgramOptimization.Result<Program> {
        let searchSpace = try ProgramOptimization.SearchSpace<Program>
            .parse(
                seed: seed,
                sites: sites
            )
        let limit = try ProgramOptimization.CandidateLimit.parse(
            maximumCandidates
        )

        return try await optimize(
            examples: examples,
            searchSpace: searchSpace,
            limit: limit,
            candidateIDPrefix: candidateIDPrefix
        )
    }

    public func optimize(
        examples: [ProgramOptimization.Example<Program>],
        searchSpace: ProgramOptimization.SearchSpace<Program>,
        limit: ProgramOptimization.CandidateLimit = .standard,
        candidateIDPrefix: String = "combination"
    ) async throws -> ProgramOptimization.Result<Program> {
        let parsedExamples = try ProgramOptimization
            .Examples<Program>
            .parse(
                examples
            )
        let generator = ProgramRealizationCandidateGenerator(
            limit: limit,
            candidateIDPrefix: candidateIDPrefix
        )
        let generated = generator.generate(
            from: searchSpace
        )
        let problem = ProgramOptimization.Problem(
            examples: parsedExamples,
            candidates: try ProgramOptimization
                .Candidates<Program>
                .parse(
                    generated
                )
        )

        return try await optimize(
            problem: problem
        )
    }

    public func optimize(
        examples: [ProgramOptimization.Example<Program>],
        candidates: [ProgramOptimization.Candidate<Program>]
    ) async throws -> ProgramOptimization.Result<Program> {
        try await optimize(
            problem: ProgramOptimization.Problem.parse(
                examples: examples,
                candidates: candidates
            )
        )
    }

    public func optimize(
        problem: ProgramOptimization.Problem<Program>
    ) async throws -> ProgramOptimization.Result<Program> {
        var trials: [ProgramOptimization.Trial] = []
        var candidateResults: [
            ProgramOptimization.CandidateResult<Program>
        ] = []

        var selected = problem.candidates.initial
        var selectedMean: AgentInferenceOptimizationScore?

        let exampleCount = Double(
            problem.examples.count
        )

        for candidate in problem.candidates {
            let firstTrialIndex = trials.count
            var meanValue = 0.0

            for (exampleIndex, example) in problem.examples.enumerated() {
                let inferenceInvoker = AgentProgramInferenceInvoker(
                    realization: candidate.realization,
                    executor: inferenceExecutor
                )
                let context = AgentProgramContext(
                    inference: inferenceInvoker
                )
                let output = try await program.run(
                    example.input,
                    in: context
                )
                let score = try await objective.score(
                    Program.self,
                    example: example,
                    output: output
                )

                meanValue += score.value / exampleCount

                trials.append(
                    ProgramOptimization.Trial(
                        candidate: candidate.id,
                        exampleIndex: exampleIndex,
                        score: score
                    )
                )
            }

            let mean = try AgentInferenceOptimizationScore(
                value: meanValue
            )
            let trialIndexes = Array(
                firstTrialIndex..<trials.count
            )

            candidateResults.append(
                ProgramOptimization.CandidateResult(
                    candidate: candidate,
                    mean: mean,
                    trialIndexes: trialIndexes
                )
            )

            if let currentSelectedMean = selectedMean {
                if mean.value > currentSelectedMean.value {
                    selected = candidate
                    selectedMean = mean
                }
            } else {
                selected = candidate
                selectedMean = mean
            }
        }

        return ProgramOptimization.Result(
            objective: objective.id,
            selected: selected,
            candidates: candidateResults,
            trials: trials
        )
    }
}
