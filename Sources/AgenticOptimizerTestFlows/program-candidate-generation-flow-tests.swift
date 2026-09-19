import Agentic
import AgenticInference
import AgenticOptimizer
import AgenticPrograms
import Foundation
import TestFlows

private struct CombinationPrepareInference: Inference {
    typealias Input = String
    typealias Output = String

    static let definition = InferenceDefinition(
        identifier: "fixture.combination_prepare",
        purpose: "Prepare a value for bounded program candidate generation."
    )
}

private struct CombinationFinalizeInference: Inference {
    typealias Input = String
    typealias Output = String

    static let definition = InferenceDefinition(
        identifier: "fixture.combination_finalize",
        purpose: "Finalize a value for bounded program candidate generation."
    )
}

private struct CombinationFixtureProgram: Program {
    typealias Input = String
    typealias Output = String

    static let definition = ProgramDefinition(
        identifier: "fixture.program_candidate_generation",
        purpose: "Two-stage program used to prove bounded inference-site combination generation."
    )

    static let prepare = InferenceSite<
        Self,
        CombinationPrepareInference
    >(
        identifier: .init(
            rawValue: "prepare"
        )
    )

    static let finalize = InferenceSite<
        Self,
        CombinationFinalizeInference
    >(
        identifier: .init(
            rawValue: "finalize"
        )
    )

    func run(
        _ input: String,
        in context: ProgramContext
    ) async throws -> String {
        let prepared = try await context.infer(
            Self.prepare,
            input: input
        )

        return try await context.infer(
            Self.finalize,
            input: prepared
        )
    }
}

private struct CombinationFixtureExecutor:
    InferenceExecuting,
    Sendable
{
    func execute(
        _ invocation: InferenceInvocation
    ) async throws -> InferenceInvocationResult {
        let inference = invocation
        let realization = invocation.realization
        let inputData = invocation.input
        let inputText = try JSONDecoder().decode(
            String.self,
            from: inputData
        )

        let outputText: String

        switch realization.instructions {
        case "identity":
            outputText = inputText

        case "uppercase":
            outputText = inputText.uppercased()

        case "constant":
            outputText = "ALPHA"

        default:
            throw CombinationFixtureError.unknownInstructions(
                realization.instructions
            )
        }

        let outputData = try JSONEncoder().encode(
            outputText
        )
        return InferenceInvocationResult(
            output: outputData,
            record: InferenceExecutionRecord(
                inference: inference.definition.identifier,
                strategy: realization.strategy,
                budget: realization.budget,
                metadata: realization.metadata
            )
        )
    }
}

private struct CombinationExactObjective:
    ProgramOptimization.Objective,
    Sendable
{
    let id: ProgramOptimization.ObjectiveID =
        "combination_exact_output"

    func score<ProgramType: Program>(
        _ program: ProgramType.Type,
        example: ProgramOptimization.Example<ProgramType>,
        output: ProgramType.Output
    ) async throws -> InferenceOptimizationScore {
        let expectedData = try JSONEncoder().encode(
            example.expectedOutput
        )
        let expected = try JSONDecoder().decode(
            String.self,
            from: expectedData
        )
        let actualData = try JSONEncoder().encode(
            output
        )
        let actual = try JSONDecoder().decode(
            String.self,
            from: actualData
        )

        return try InferenceOptimizationScore(
            value: expected == actual ? 1.0 : 0.0
        )
    }
}

private enum CombinationFixtureError:
    Error,
    Sendable
{
    case unknownInstructions(String)
}

extension OptimizerFlowTesting {
    static func runProgramCandidateGeneration()
        async throws
        -> [TestFlowDiagnostic]
    {
        let identity = InferenceRealizationConfiguration(
            strategy: .direct,
            instructions: "identity",
            budget: .singleAttempt
        )
        let uppercase = InferenceRealizationConfiguration(
            strategy: .direct,
            instructions: "uppercase",
            budget: .singleAttempt
        )
        let constant = InferenceRealizationConfiguration(
            strategy: .direct,
            instructions: "constant",
            budget: .singleAttempt
        )

        let seed = try ProgramRealization<CombinationFixtureProgram>(
            bindings: [
                .init(
                    CombinationFixtureProgram.prepare,
                    realization: fixtureInferenceRealization(
                        CombinationPrepareInference.self,
                        identifier: "prepare.identity",
                        configuration: identity
                    )
                ),
                .init(
                    CombinationFixtureProgram.finalize,
                    realization: fixtureInferenceRealization(
                        CombinationFinalizeInference.self,
                        identifier: "finalize.identity",
                        configuration: identity
                    )
                )
            ]
        )

        let sites: [ProgramOptimization.SiteCandidates<CombinationFixtureProgram>] = [
            .init(
                CombinationFixtureProgram.prepare,
                candidates: [
                    InferenceRealizationCandidate(
                        identifier: "prepare_identity",
                        realization: identity,
                        source: .seed
                    ),
                    InferenceRealizationCandidate(
                        identifier: "prepare_uppercase",
                        realization: uppercase,
                        source: .instruction_variant,
                        metadata: [
                            "origin": "prepare_optimizer",
                        ]
                    ),
                ]
            ),
            .init(
                CombinationFixtureProgram.finalize,
                candidates: [
                    InferenceRealizationCandidate(
                        identifier: "finalize_identity",
                        realization: identity,
                        source: .seed
                    ),
                    InferenceRealizationCandidate(
                        identifier: "finalize_uppercase",
                        realization: uppercase,
                        source: .demonstration_variant,
                        metadata: [
                            "origin": "finalize_optimizer",
                        ]
                    ),
                    InferenceRealizationCandidate(
                        identifier: "finalize_constant",
                        realization: constant,
                        source: .supplied
                    ),
                ]
            ),
        ]

        let searchSpace = try ProgramOptimization
            .SearchSpace<CombinationFixtureProgram>
            .parse(
                seed: seed,
                sites: sites
            )
        let limit = try ProgramOptimization.CandidateLimit.parse(
            4
        )
        let generator = ProgramRealizationCandidateGenerator(
            limit: limit,
            candidateIDPrefix: "program"
        )
        let generated = generator.generate(
            from: searchSpace
        )

        try Expect.equal(
            generated.count,
            4,
            "program combination generation respects its candidate budget"
        )
        try Expect.equal(
            generated.map(\.id.rawValue),
            [
                "program_1",
                "program_2",
                "program_3",
                "program_4",
            ],
            "program combinations receive deterministic stable identities"
        )
        try Expect.equal(
            generated[0].selections.map {
                $0.candidate.identifier.rawValue
            },
            [
                "prepare_identity",
                "finalize_identity",
            ],
            "first combination selects the first candidate at every inference site"
        )
        try Expect.equal(
            generated[1].selections.map {
                $0.candidate.identifier.rawValue
            },
            [
                "prepare_identity",
                "finalize_uppercase",
            ],
            "last inference site varies fastest in deterministic combination order"
        )
        try Expect.equal(
            generated[2].selections.map {
                $0.candidate.identifier.rawValue
            },
            [
                "prepare_identity",
                "finalize_constant",
            ],
            "generator continues deterministically through the final-site candidate space"
        )
        try Expect.equal(
            generated[3].selections.map {
                $0.candidate.identifier.rawValue
            },
            [
                "prepare_uppercase",
                "finalize_identity",
            ],
            "bounded generation advances the preceding site after exhausting the final site"
        )
        try Expect.equal(
            generated[1].selections[1].candidate.source,
            .demonstration_variant,
            "whole-program candidate retains inference candidate source provenance"
        )
        try Expect.equal(
            generated[1].selections[1].candidate.metadata[
                "origin"
            ],
            "finalize_optimizer",
            "whole-program candidate retains exact inference candidate metadata"
        )
        try Expect.equal(
            generated[1].realization.binding(
                for: CombinationFixtureProgram.prepare
            )?.configuration.instructions,
            "identity",
            "generated program realization installs the selected prepare realization"
        )
        try Expect.equal(
            generated[1].realization.binding(
                for: CombinationFixtureProgram.finalize
            )?.configuration.instructions,
            "uppercase",
            "generated program realization installs the selected finalize realization"
        )

        let examples: [
            ProgramOptimization.Example<CombinationFixtureProgram>
        ] = [
            .init(
                input: "alpha",
                expectedOutput: "ALPHA"
            ),
            .init(
                input: "beta",
                expectedOutput: "BETA"
            ),
        ]
        let search = ProgramRealizationSearch(
            program: CombinationFixtureProgram(),
            inferenceExecutor: CombinationFixtureExecutor(),
            objective: CombinationExactObjective()
        )
        let result = try await search.optimize(
            examples: examples,
            searchSpace: searchSpace,
            limit: limit,
            candidateIDPrefix: "program"
        )

        try Expect.equal(
            result.candidates.count,
            4,
            "whole-program search evaluates the bounded generated candidate set"
        )
        try Expect.equal(
            result.trials.count,
            8,
            "whole-program search evaluates every generated combination against every example"
        )
        try Expect.equal(
            result.candidates[0].meanScore,
            0.0,
            "identity identity combination fails the uppercase objective"
        )
        try Expect.equal(
            result.candidates[1].meanScore,
            1.0,
            "identity uppercase combination satisfies the whole-program objective"
        )
        try Expect.equal(
            result.candidates[2].meanScore,
            0.5,
            "constant finalization only satisfies one optimization example"
        )
        try Expect.equal(
            result.candidates[3].meanScore,
            1.0,
            "uppercase identity combination independently satisfies the objective"
        )
        try Expect.equal(
            result.selected.id,
            ProgramOptimization.CandidateID(
                "program_2"
            ),
            "stable whole-program search tie breaking selects the first best generated combination"
        )
        try Expect.equal(
            result.selected.selections[0].candidate.identifier,
            InferenceRealizationCandidateIdentifier(
                "prepare_identity"
            ),
            "selected result retains prepare-site inference candidate provenance"
        )
        try Expect.equal(
            result.selected.selections[1].candidate.identifier,
            InferenceRealizationCandidateIdentifier(
                "finalize_uppercase"
            ),
            "selected result retains finalize-site inference candidate provenance"
        )

        var duplicateSiteRejected = false

        do {
            _ = try ProgramOptimization
                .SearchSpace<CombinationFixtureProgram>
                .parse(
                    seed: seed,
                    sites: [
                        sites[0],
                        sites[0],
                    ]
                )
        } catch let error as ProgramOptimization.SearchSpaceError {
            switch error {
            case .duplicateSite:
                duplicateSiteRejected = true

            default:
                break
            }
        }

        try Expect.equal(
            duplicateSiteRejected,
            true,
            "search-space parsing rejects ambiguous duplicate sites before generation"
        )

        var emptySiteRejected = false

        do {
            _ = try ProgramOptimization
                .SearchSpace<CombinationFixtureProgram>
                .parse(
                    seed: seed,
                    sites: [
                        ProgramOptimization.SiteCandidates(
                            CombinationFixtureProgram.prepare,
                            candidates: []
                        ),
                    ]
                )
        } catch let error as ProgramOptimization.SearchSpaceError {
            switch error {
            case .emptySiteCandidates:
                emptySiteRejected = true

            default:
                break
            }
        }

        try Expect.equal(
            emptySiteRejected,
            true,
            "search-space parsing rejects empty inference-site candidate spaces before generation"
        )

        var invalidLimitRejected = false

        do {
            _ = try ProgramOptimization.CandidateLimit.parse(
                0
            )
        } catch let error as ProgramOptimization.CandidateLimitError {
            switch error {
            case .nonPositive:
                invalidLimitRejected = true
            }
        }

        try Expect.equal(
            invalidLimitRejected,
            true,
            "candidate-limit parsing prevents non-positive generation limits"
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
            "candidate-limit Codable round trip preserves the parsed positive value"
        )

        return [
            .field(
                "generated",
                String(generated.count)
            ),
            .field(
                "bounded",
                String(generated.count == 4)
            ),
            .field(
                "trials",
                String(result.trials.count)
            ),
            .field(
                "selected",
                result.selected.id.rawValue
            ),
            .field(
                "prepare",
                result.selected.selections[0]
                    .candidate
                    .identifier
                    .rawValue
            ),
            .field(
                "finalize",
                result.selected.selections[1]
                    .candidate
                    .identifier
                    .rawValue
            ),
            .field(
                "duplicate_site_rejected",
                String(duplicateSiteRejected)
            ),
            .field(
                "empty_site_rejected",
                String(emptySiteRejected)
            ),
            .field(
                "invalid_limit_rejected",
                String(invalidLimitRejected)
            ),
        ]
    }
}