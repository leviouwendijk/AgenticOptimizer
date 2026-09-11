import AgenticInference
import AgenticOptimizer
import AgenticPrograms
import Foundation
import TestFlows

private struct CombinationPrepareInference: AgentInference {
    typealias Input = String
    typealias Output = String

    static let definition = AgentInferenceDefinition(
        identifier: "fixture.combination_prepare",
        purpose: "Prepare a value for bounded program candidate generation."
    )
}

private struct CombinationFinalizeInference: AgentInference {
    typealias Input = String
    typealias Output = String

    static let definition = AgentInferenceDefinition(
        identifier: "fixture.combination_finalize",
        purpose: "Finalize a value for bounded program candidate generation."
    )
}

private struct CombinationFixtureProgram: AgentProgram {
    typealias Input = String
    typealias Output = String

    static let descriptor = AgentProgramDescriptor(
        identifier: "fixture.program_candidate_generation",
        title: "Program Candidate Generation Fixture",
        summary: "Two-stage program used to prove bounded inference-site combination generation."
    )

    func run(
        _ input: String,
        in context: AgentProgramContext
    ) async throws -> String {
        let prepared = try await context.infer(
            CombinationPrepareInference.self,
            at: "prepare",
            input: input
        )

        return try await context.infer(
            CombinationFinalizeInference.self,
            at: "finalize",
            input: prepared
        )
    }
}

private struct CombinationFixtureExecutor:
    AgentInferenceExecuting,
    Sendable
{
    func execute<Inference: AgentInference>(
        _ inference: Inference.Type,
        input: Inference.Input,
        realization: AgentInferenceRealization
    ) async throws -> AgentInferenceExecutionResult<Inference.Output> {
        let inputData = try JSONEncoder().encode(
            input
        )
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
        let output = try JSONDecoder().decode(
            Inference.Output.self,
            from: outputData
        )

        return AgentInferenceExecutionResult(
            output: output,
            record: AgentInferenceExecutionRecord(
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

    func score<Program: AgentProgram>(
        _ program: Program.Type,
        example: ProgramOptimization.Example<Program>,
        output: Program.Output
    ) async throws -> AgentInferenceOptimizationScore {
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

        return AgentInferenceOptimizationScore(
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

extension AgenticOptimizerFlowTesting {
    static func runProgramCandidateGeneration()
        async throws
        -> [TestFlowDiagnostic]
    {
        let identity = AgentInferenceRealization(
            strategy: .direct,
            modelSelection: .executor,
            instructions: "identity",
            budget: .singleAttempt
        )
        let uppercase = AgentInferenceRealization(
            strategy: .direct,
            modelSelection: .executor,
            instructions: "uppercase",
            budget: .singleAttempt
        )
        let constant = AgentInferenceRealization(
            strategy: .direct,
            modelSelection: .executor,
            instructions: "constant",
            budget: .singleAttempt
        )

        let seed = AgentProgramRealization<CombinationFixtureProgram>(
            id: "fixture.program.combination_seed",
            inferences: [
                AgentInferenceRealizationBinding(
                    site: "prepare",
                    inference: CombinationPrepareInference.definition.identifier,
                    realization: identity
                ),
                AgentInferenceRealizationBinding(
                    site: "finalize",
                    inference: CombinationFinalizeInference.definition.identifier,
                    realization: identity
                ),
            ],
            metadata: [
                "seed_marker": "preserved",
            ]
        )

        let sites: [ProgramOptimization.SiteCandidates] = [
            .init(
                site: "prepare",
                inference: CombinationPrepareInference.definition.identifier,
                candidates: [
                    AgentInferenceRealizationCandidate(
                        identifier: "prepare_identity",
                        realization: identity,
                        source: .seed
                    ),
                    AgentInferenceRealizationCandidate(
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
                site: "finalize",
                inference: CombinationFinalizeInference.definition.identifier,
                candidates: [
                    AgentInferenceRealizationCandidate(
                        identifier: "finalize_identity",
                        realization: identity,
                        source: .seed
                    ),
                    AgentInferenceRealizationCandidate(
                        identifier: "finalize_uppercase",
                        realization: uppercase,
                        source: .demonstration_variant,
                        metadata: [
                            "origin": "finalize_optimizer",
                        ]
                    ),
                    AgentInferenceRealizationCandidate(
                        identifier: "finalize_constant",
                        realization: constant,
                        source: .supplied
                    ),
                ]
            ),
        ]

        let generator = ProgramRealizationCandidateGenerator(
            maximumCandidates: 4,
            candidateIDPrefix: "program"
        )
        let generated = try generator.generate(
            seed: seed,
            sites: sites
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
            generated[1].realization.metadata[
                "seed_marker"
            ],
            "preserved",
            "combination generation preserves program realization metadata"
        )
        try Expect.equal(
            generated[1].realization.realization(
                at: "prepare"
            )?.instructions,
            "identity",
            "generated program realization installs the selected prepare realization"
        )
        try Expect.equal(
            generated[1].realization.realization(
                at: "finalize"
            )?.instructions,
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
            seed: seed,
            sites: sites,
            maximumCandidates: 4,
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
            AgentInferenceRealizationCandidateIdentifier(
                "prepare_identity"
            ),
            "selected result retains prepare-site inference candidate provenance"
        )
        try Expect.equal(
            result.selected.selections[1].candidate.identifier,
            AgentInferenceRealizationCandidateIdentifier(
                "finalize_uppercase"
            ),
            "selected result retains finalize-site inference candidate provenance"
        )

        var duplicateSiteRejected = false

        do {
            _ = try generator.generate(
                seed: seed,
                sites: [
                    sites[0],
                    sites[0],
                ]
            )
        } catch let error as ProgramRealizationCandidateGeneratorError {
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
            "program combination generation rejects ambiguous duplicate site spaces"
        )

        var emptySiteRejected = false

        do {
            _ = try generator.generate(
                seed: seed,
                sites: [
                    ProgramOptimization.SiteCandidates(
                        site: "prepare",
                        inference: CombinationPrepareInference.definition.identifier,
                        candidates: []
                    ),
                ]
            )
        } catch let error as ProgramRealizationCandidateGeneratorError {
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
            "program combination generation rejects empty inference-site search spaces"
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
        ]
    }
}
