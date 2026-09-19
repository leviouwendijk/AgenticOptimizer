import Agentic
import AgenticInference
import AgenticPrograms

public struct ProgramRealizationSearch<ProgramType: Program>: Sendable {
    private let program: ProgramType
    private let inferenceExecutor: any InferenceExecuting
    private let objective: any ProgramOptimization.Objective

    public init(
        program: ProgramType,
        inferenceExecutor: any InferenceExecuting,
        objective: any ProgramOptimization.Objective
    ) {
        self.program = program
        self.inferenceExecutor = inferenceExecutor
        self.objective = objective
    }

    public func optimize(
        dataset: ProgramOptimization.Dataset<ProgramType>,
        seed: ProgramRealization<ProgramType>,
        sites: [ProgramOptimization.SiteCandidates<ProgramType>],
        maximumCandidates: Int = 64,
        candidateIDPrefix: String = "combination"
    ) async throws -> ProgramOptimization.Report<ProgramType> {
        let searchSpace = try ProgramOptimization.SearchSpace<ProgramType>
            .parse(
                seed: seed,
                sites: sites
            )
        let limit = try ProgramOptimization.CandidateLimit.parse(
            maximumCandidates
        )

        return try await optimize(
            dataset: dataset,
            searchSpace: searchSpace,
            limit: limit,
            candidateIDPrefix: candidateIDPrefix
        )
    }

    public func optimize(
        dataset: ProgramOptimization.Dataset<ProgramType>,
        searchSpace: ProgramOptimization.SearchSpace<ProgramType>,
        limit: ProgramOptimization.CandidateLimit = .standard,
        candidateIDPrefix: String = "combination"
    ) async throws -> ProgramOptimization.Report<ProgramType> {
        let generator = ProgramRealizationCandidateGenerator(
            limit: limit,
            candidateIDPrefix: candidateIDPrefix
        )
        let generated = generator.generate(
            from: searchSpace
        )

        return try await optimize(
            dataset: dataset,
            candidates: generated
        )
    }

    public func optimize(
        dataset: ProgramOptimization.Dataset<ProgramType>,
        candidates: [ProgramOptimization.Candidate<ProgramType>]
    ) async throws -> ProgramOptimization.Report<ProgramType> {
        let optimization = try await optimize(
            problem: ProgramOptimization.Problem(
                examples: dataset.training,
                candidates: try ProgramOptimization
                    .Candidates<ProgramType>
                    .parse(
                        candidates
                    )
            )
        )
        let evaluation = try await evaluate(
            candidate: optimization.selected,
            examples: dataset.evaluation
        )

        return ProgramOptimization.Report(
            optimization: optimization,
            evaluation: evaluation
        )
    }

    public func optimize(
        examples: [ProgramOptimization.Example<ProgramType>],
        seed: ProgramRealization<ProgramType>,
        sites: [ProgramOptimization.SiteCandidates<ProgramType>],
        maximumCandidates: Int = 64,
        candidateIDPrefix: String = "combination"
    ) async throws -> ProgramOptimization.Result<ProgramType> {
        let searchSpace = try ProgramOptimization.SearchSpace<ProgramType>
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
        examples: [ProgramOptimization.Example<ProgramType>],
        searchSpace: ProgramOptimization.SearchSpace<ProgramType>,
        limit: ProgramOptimization.CandidateLimit = .standard,
        candidateIDPrefix: String = "combination"
    ) async throws -> ProgramOptimization.Result<ProgramType> {
        let parsedExamples = try ProgramOptimization
            .Examples<ProgramType>
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
                .Candidates<ProgramType>
                .parse(
                    generated
                )
        )

        return try await optimize(
            problem: problem
        )
    }

    public func optimize(
        examples: [ProgramOptimization.Example<ProgramType>],
        candidates: [ProgramOptimization.Candidate<ProgramType>]
    ) async throws -> ProgramOptimization.Result<ProgramType> {
        try await optimize(
            problem: ProgramOptimization.Problem.parse(
                examples: examples,
                candidates: candidates
            )
        )
    }

    public func optimize(
        problem: ProgramOptimization.Problem<ProgramType>
    ) async throws -> ProgramOptimization.Result<ProgramType> {
        var trials: [ProgramOptimization.Trial] = []
        var candidateResults: [
            ProgramOptimization.CandidateResult<ProgramType>
        ] = []

        var selected = problem.candidates.initial
        var selectedMean: InferenceOptimizationScore?

        for candidate in problem.candidates {
            let evaluation = try await evaluate(
                candidate: candidate,
                examples: problem.examples
            )
            let firstTrialIndex = trials.count

            trials.append(
                contentsOf: evaluation.trials
            )

            candidateResults.append(
                ProgramOptimization.CandidateResult(
                    candidate: candidate,
                    mean: evaluation.mean,
                    trialIndexes: Array(
                        firstTrialIndex..<trials.count
                    )
                )
            )

            if let currentSelectedMean = selectedMean {
                if evaluation.mean.value > currentSelectedMean.value {
                    selected = candidate
                    selectedMean = evaluation.mean
                }
            } else {
                selected = candidate
                selectedMean = evaluation.mean
            }
        }

        return ProgramOptimization.Result(
            objective: objective.id,
            selected: selected,
            candidates: candidateResults,
            trials: trials
        )
    }

    public func evaluate(
        candidate: ProgramOptimization.Candidate<ProgramType>,
        examples: ProgramOptimization.Examples<ProgramType>
    ) async throws -> ProgramOptimization.Evaluation<ProgramType> {
        var trials: [ProgramOptimization.Trial] = []
        var meanValue = 0.0
        let exampleCount = Double(
            examples.count
        )
        let clock = ContinuousClock()

        for (exampleIndex, example) in examples.enumerated() {
            let recorder = ProgramOptimizationExecutionRecorder()
            let recordingExecutor =
                ProgramOptimizationRecordingInferenceExecutor(
                    base: inferenceExecutor,
                    recorder: recorder
                )
            let inferenceInvoker = ProgramInferenceInvoker(
                realization: candidate.realization,
                executor: recordingExecutor
            )
            let context = ProgramContext(
                inference: inferenceInvoker
            )
            let startedAt = clock.now
            let output = try await program.run(
                example.input,
                in: context
            )
            let duration = startedAt.duration(
                to: clock.now
            )
            let durationSeconds =
                max(
                    0,
                    Double(duration.components.seconds)
                        + Double(duration.components.attoseconds)
                            / 1_000_000_000_000_000_000
                )
            let executions = await recorder.snapshot()
            let score = try await objective.score(
                ProgramType.self,
                example: example,
                output: output
            )

            meanValue += score.value / exampleCount

            trials.append(
                ProgramOptimization.Trial(
                    candidate: candidate.id,
                    exampleIndex: exampleIndex,
                    score: score,
                    executions: executions,
                    durationSeconds: durationSeconds
                )
            )
        }

        return ProgramOptimization.Evaluation(
            candidate: candidate,
            mean: try InferenceOptimizationScore(
                value: meanValue
            ),
            trials: trials
        )
    }
}