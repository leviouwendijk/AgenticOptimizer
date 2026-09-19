import Agentic
import AgenticInference
import AgenticOptimizer
import AgenticPrograms
import Foundation
import TestFlows

private struct OptimizationInputParsingInference: Inference {
    typealias Input = String
    typealias Output = String

    static let definition = InferenceDefinition(
        identifier: "fixture.optimization_input_parsing",
        purpose: "Exercise parsed optimizer inputs."
    )
}

private struct OptimizationInputParsingProgram: Program {
    typealias Input = String
    typealias Output = String

    static let definition = ProgramDefinition(
        identifier: "fixture.optimization_input_parsing_program",
        purpose: "Exercise parsed whole-program optimizer inputs."
    )

    func run(
        _ input: String,
        in context: ProgramContext
    ) async throws -> String {
        input
    }
}

extension OptimizerFlowTesting {
    static func runOptimizationInputParsing()
        async throws
        -> [TestFlowDiagnostic]
    {
        let score = try InferenceOptimizationScore(
            value: 1.0,
            metadata: [
                "marker": "finite",
            ]
        )
        let decodedScore = try JSONDecoder().decode(
            InferenceOptimizationScore.self,
            from: JSONEncoder().encode(
                score
            )
        )

        try Expect.equal(
            decodedScore,
            score,
            "finite optimization scores survive durable codec round trip"
        )

        var nonFiniteScoreRejected = false

        do {
            _ = try InferenceOptimizationScore(
                value: .nan
            )
        } catch InferenceOptimizationScoreParsingError
            .nonFinite {
            nonFiniteScoreRejected = true
        }

        try Expect.equal(
            nonFiniteScoreRejected,
            true,
            "non-finite optimization scores are rejected at parsing"
        )

        let scoreDecoder = JSONDecoder()
        scoreDecoder.nonConformingFloatDecodingStrategy =
            .convertFromString(
                positiveInfinity: "Infinity",
                negativeInfinity: "-Infinity",
                nan: "NaN"
            )
        let invalidScoreData = Data(
            """
            {
              "value": "Infinity",
              "metadata": {}
            }
            """.utf8
        )
        var nonFiniteScoreDecodeRejected = false

        do {
            _ = try scoreDecoder.decode(
                InferenceOptimizationScore.self,
                from: invalidScoreData
            )
        } catch InferenceOptimizationScoreParsingError
            .nonFinite {
            nonFiniteScoreDecodeRejected = true
        }

        try Expect.equal(
            nonFiniteScoreDecodeRejected,
            true,
            "optimization score decoding cannot bypass finite-score parsing"
        )

        let limit = try ProgramOptimization.CandidateLimit.parse(
            4
        )
        let decodedLimit = try JSONDecoder().decode(
            ProgramOptimization.CandidateLimit.self,
            from: JSONEncoder().encode(
                limit
            )
        )

        try Expect.equal(
            decodedLimit,
            limit,
            "parsed program candidate limits remain Codable"
        )

        let invalidLimitData = Data(
            """
            {
              "value": 0
            }
            """.utf8
        )
        var invalidLimitDecodeRejected = false

        do {
            _ = try JSONDecoder().decode(
                ProgramOptimization.CandidateLimit.self,
                from: invalidLimitData
            )
        } catch ProgramOptimization.CandidateLimitError
            .nonPositive {
            invalidLimitDecodeRejected = true
        }

        try Expect.equal(
            invalidLimitDecodeRejected,
            true,
            "candidate-limit decoding cannot bypass positive-value parsing"
        )

        let realization = InferenceRealizationConfiguration(
            strategy: .direct,
            instructions: "fixture",
            budget: .singleAttempt
        )
        let inferenceCandidate = InferenceRealizationCandidate(
            identifier: "candidate",
            realization: realization
        )
        let inferenceExample =
            InferenceOptimizationExample<
                OptimizationInputParsingInference
            >(
                input: "input",
                expectedOutput: "output"
            )
        let inferenceProblem =
            try InferenceOptimizationProblem<
                OptimizationInputParsingInference
            >.parse(
                examples: [
                    inferenceExample,
                ],
                candidates: [
                    inferenceCandidate,
                ]
            )

        try Expect.equal(
            inferenceProblem.examples.count,
            1,
            "parsed inference optimization problem retains non-empty examples"
        )
        try Expect.equal(
            inferenceProblem.candidates.count,
            1,
            "parsed inference optimization problem retains non-empty candidates"
        )

        var emptyInferenceExamplesRejected = false

        do {
            _ = try InferenceOptimizationProblem<
                OptimizationInputParsingInference
            >.parse(
                examples: [],
                candidates: [
                    inferenceCandidate,
                ]
            )
        } catch InferenceOptimizationProblemParsingError
            .noExamples {
            emptyInferenceExamplesRejected = true
        }

        var emptyInferenceCandidatesRejected = false

        do {
            _ = try InferenceOptimizationProblem<
                OptimizationInputParsingInference
            >.parse(
                examples: [
                    inferenceExample,
                ],
                candidates: []
            )
        } catch InferenceOptimizationProblemParsingError
            .noCandidates {
            emptyInferenceCandidatesRejected = true
        }

        var duplicateInferenceCandidateRejected = false

        do {
            _ = try InferenceOptimizationProblem<
                OptimizationInputParsingInference
            >.parse(
                examples: [
                    inferenceExample,
                ],
                candidates: [
                    inferenceCandidate,
                    inferenceCandidate,
                ]
            )
        } catch InferenceOptimizationProblemParsingError
            .duplicateCandidateIdentifier(let identifier) {
            duplicateInferenceCandidateRejected =
                identifier == inferenceCandidate.identifier
        }

        let programCandidate =
            ProgramOptimization.Candidate<
                OptimizationInputParsingProgram
            >(
                id: "program_candidate",
                realization:
                    try ProgramRealization<OptimizationInputParsingProgram>()
            )
        let programExample =
            ProgramOptimization.Example<
                OptimizationInputParsingProgram
            >(
                input: "input",
                expectedOutput: "output"
            )
        let programProblem =
            try ProgramOptimization
                .Problem<OptimizationInputParsingProgram>
                .parse(
                    examples: [
                        programExample,
                    ],
                    candidates: [
                        programCandidate,
                    ]
                )

        try Expect.equal(
            programProblem.examples.count,
            1,
            "parsed program optimization problem retains non-empty examples"
        )
        try Expect.equal(
            programProblem.candidates.count,
            1,
            "parsed program optimization problem retains non-empty candidates"
        )

        var emptyProgramExamplesRejected = false

        do {
            _ = try ProgramOptimization
                .Problem<OptimizationInputParsingProgram>
                .parse(
                    examples: [],
                    candidates: [
                        programCandidate,
                    ]
                )
        } catch ProgramOptimization.ProblemParsingError
            .noExamples {
            emptyProgramExamplesRejected = true
        }

        var emptyProgramCandidatesRejected = false

        do {
            _ = try ProgramOptimization
                .Problem<OptimizationInputParsingProgram>
                .parse(
                    examples: [
                        programExample,
                    ],
                    candidates: []
                )
        } catch ProgramOptimization.ProblemParsingError
            .noCandidates {
            emptyProgramCandidatesRejected = true
        }

        var duplicateProgramCandidateRejected = false

        do {
            _ = try ProgramOptimization
                .Problem<OptimizationInputParsingProgram>
                .parse(
                    examples: [
                        programExample,
                    ],
                    candidates: [
                        programCandidate,
                        programCandidate,
                    ]
                )
        } catch ProgramOptimization.ProblemParsingError
            .duplicateCandidateIdentifier(let identifier) {
            duplicateProgramCandidateRejected =
                identifier == programCandidate.id
        }

        try Expect.equal(
            emptyInferenceExamplesRejected
                && emptyInferenceCandidatesRejected
                && duplicateInferenceCandidateRejected,
            true,
            "inference optimization problem parsing rejects structurally ambiguous or empty input"
        )
        try Expect.equal(
            emptyProgramExamplesRejected
                && emptyProgramCandidatesRejected
                && duplicateProgramCandidateRejected,
            true,
            "program optimization problem parsing rejects structurally ambiguous or empty input"
        )

        return [
            .field(
                "score_parse",
                String(
                    nonFiniteScoreRejected
                        && nonFiniteScoreDecodeRejected
                )
            ),
            .field(
                "candidate_limit_codable",
                String(
                    decodedLimit == limit
                        && invalidLimitDecodeRejected
                )
            ),
            .field(
                "inference_problem_parse",
                String(
                    emptyInferenceExamplesRejected
                        && emptyInferenceCandidatesRejected
                        && duplicateInferenceCandidateRejected
                )
            ),
            .field(
                "program_problem_parse",
                String(
                    emptyProgramExamplesRejected
                        && emptyProgramCandidatesRejected
                        && duplicateProgramCandidateRejected
                )
            ),
        ]
    }
}