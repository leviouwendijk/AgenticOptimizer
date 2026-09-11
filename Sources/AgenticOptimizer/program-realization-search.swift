import AgenticInference
import AgenticPrograms
import Foundation

public enum ProgramRealizationSearchError:
    Error,
    Sendable,
    LocalizedError
{
    case no_candidates
    case no_examples
    case invalid_score(
        candidate: ProgramOptimization.CandidateID,
        exampleIndex: Int
    )
    case no_selection

    public var errorDescription: String? {
        switch self {
        case .no_candidates:
            return "Program realization optimization requires at least one candidate."

        case .no_examples:
            return "Program realization optimization requires at least one example."

        case .invalid_score(
            let candidate,
            let exampleIndex
        ):
            return "Program optimization returned a non-finite score for candidate '\(candidate.rawValue)' on example \(exampleIndex)."

        case .no_selection:
            return "Program realization optimization completed without selecting a candidate."
        }
    }
}

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
        candidates: [ProgramOptimization.Candidate<Program>]
    ) async throws -> ProgramOptimization.Result<Program> {
        guard !candidates.isEmpty else {
            throw ProgramRealizationSearchError.no_candidates
        }

        guard !examples.isEmpty else {
            throw ProgramRealizationSearchError.no_examples
        }

        var trials: [ProgramOptimization.Trial] = []
        var candidateResults: [
            ProgramOptimization.CandidateResult<Program>
        ] = []

        var selected: ProgramOptimization.Candidate<Program>?
        var selectedMeanScore: Double?

        for candidate in candidates {
            let firstTrialIndex = trials.count
            var totalScore = 0.0

            for (exampleIndex, example) in examples.enumerated() {
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

                guard score.value.isFinite else {
                    throw ProgramRealizationSearchError.invalid_score(
                        candidate: candidate.id,
                        exampleIndex: exampleIndex
                    )
                }

                totalScore += score.value

                trials.append(
                    ProgramOptimization.Trial(
                        candidate: candidate.id,
                        exampleIndex: exampleIndex,
                        score: score
                    )
                )
            }

            let meanScore = totalScore / Double(examples.count)
            let trialIndexes = Array(
                firstTrialIndex..<trials.count
            )

            candidateResults.append(
                ProgramOptimization.CandidateResult(
                    candidate: candidate,
                    meanScore: meanScore,
                    trialIndexes: trialIndexes
                )
            )

            if let currentSelectedMeanScore = selectedMeanScore {
                if meanScore > currentSelectedMeanScore {
                    selected = candidate
                    selectedMeanScore = meanScore
                }
            } else {
                selected = candidate
                selectedMeanScore = meanScore
            }
        }

        guard let selected else {
            throw ProgramRealizationSearchError.no_selection
        }

        return ProgramOptimization.Result(
            objective: objective.id,
            selected: selected,
            candidates: candidateResults,
            trials: trials
        )
    }
}
