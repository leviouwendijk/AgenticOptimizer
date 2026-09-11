import AgenticInference
import Foundation
import Primitives

public struct AgentInferenceDemonstrationBootstrapTrial:
    Sendable,
    Codable,
    Hashable
{
    public var exampleIndex: Int
    public var demonstration: AgentInferenceDemonstration
    public var score: AgentInferenceOptimizationScore
    public var execution: AgentInferenceExecutionRecord
    public var accepted: Bool

    public init(
        exampleIndex: Int,
        demonstration: AgentInferenceDemonstration,
        score: AgentInferenceOptimizationScore,
        execution: AgentInferenceExecutionRecord,
        accepted: Bool
    ) {
        self.exampleIndex = exampleIndex
        self.demonstration = demonstration
        self.score = score
        self.execution = execution
        self.accepted = accepted
    }
}

public struct AgentInferenceDemonstrationBootstrapRecord:
    Sendable,
    Codable,
    Hashable
{
    public var inference: AgentInferenceIdentifier
    public var objective: AgentInferenceOptimizationObjectiveIdentifier
    public var teacher: AgentInferenceRealization
    public var minimumScore: Double
    public var trials: [AgentInferenceDemonstrationBootstrapTrial]

    public init(
        inference: AgentInferenceIdentifier,
        objective: AgentInferenceOptimizationObjectiveIdentifier,
        teacher: AgentInferenceRealization,
        minimumScore: Double,
        trials: [AgentInferenceDemonstrationBootstrapTrial]
    ) {
        self.inference = inference
        self.objective = objective
        self.teacher = teacher
        self.minimumScore = minimumScore
        self.trials = trials
    }

    public var acceptedCount: Int {
        trials.reduce(
            into: 0
        ) { count, trial in
            if trial.accepted {
                count += 1
            }
        }
    }
}

public enum AgentInferenceDemonstrationBootstrapGeneratorError:
    Error,
    Sendable,
    LocalizedError
{
    case invalidMinimumScore(Double)
    case invalidScore(
        exampleIndex: Int
    )
    case duplicateCandidateIdentifier(
        AgentInferenceRealizationCandidateIdentifier
    )
    case noAcceptedDemonstrations

    public var errorDescription: String? {
        switch self {
        case .invalidMinimumScore(let score):
            return "Demonstration bootstrap requires a finite minimum score; received \(score)."

        case .invalidScore(let exampleIndex):
            return "Demonstration bootstrap objective returned a non-finite score for example \(exampleIndex)."

        case .duplicateCandidateIdentifier(let identifier):
            return "Demonstration bootstrap candidate identifier '\(identifier.rawValue)' collides with another generated candidate."

        case .noAcceptedDemonstrations:
            return "Demonstration bootstrap produced no accepted demonstrations and no seed candidate was requested."
        }
    }
}

public struct AgentInferenceDemonstrationBootstrapGenerator:
    AgentInferenceRealizationCandidateGenerating,
    Sendable
{
    private let executor: any AgentInferenceExecuting
    private let objective: any AgentInferenceOptimizationObjective

    public var teacher: AgentInferenceRealization
    public var minimumScore: Double
    public var includeSeed: Bool
    public var seedIdentifier: AgentInferenceRealizationCandidateIdentifier
    public var bootstrapIdentifier: AgentInferenceRealizationCandidateIdentifier

    public init(
        executor: any AgentInferenceExecuting,
        objective: any AgentInferenceOptimizationObjective,
        teacher: AgentInferenceRealization,
        minimumScore: Double,
        includeSeed: Bool = true,
        seedIdentifier: AgentInferenceRealizationCandidateIdentifier = "seed",
        bootstrapIdentifier: AgentInferenceRealizationCandidateIdentifier = "bootstrapped"
    ) {
        self.executor = executor
        self.objective = objective
        self.teacher = teacher
        self.minimumScore = minimumScore
        self.includeSeed = includeSeed
        self.seedIdentifier = seedIdentifier
        self.bootstrapIdentifier = bootstrapIdentifier
    }

    public func generate<Inference: AgentInference>(
        _ inference: Inference.Type,
        examples: [AgentInferenceOptimizationExample<Inference>],
        seed: AgentInferenceRealization
    ) async throws -> [AgentInferenceRealizationCandidate] {
        guard minimumScore.isFinite else {
            throw AgentInferenceDemonstrationBootstrapGeneratorError
                .invalidMinimumScore(
                    minimumScore
                )
        }

        var identifiers: Set<AgentInferenceRealizationCandidateIdentifier> = []
        var candidates: [AgentInferenceRealizationCandidate] = []

        if includeSeed {
            try insertIdentifier(
                seedIdentifier,
                into: &identifiers
            )

            candidates.append(
                AgentInferenceRealizationCandidate(
                    identifier: seedIdentifier,
                    realization: seed,
                    source: .seed
                )
            )
        }

        var acceptedDemonstrations: [AgentInferenceDemonstration] = []
        var trials: [AgentInferenceDemonstrationBootstrapTrial] = []

        for (exampleIndex, example) in examples.enumerated() {
            let execution = try await executor.execute(
                inference,
                input: example.input,
                realization: teacher
            )
            let score = try await objective.score(
                inference,
                example: example,
                result: execution
            )

            guard score.value.isFinite else {
                throw AgentInferenceDemonstrationBootstrapGeneratorError
                    .invalidScore(
                        exampleIndex: exampleIndex
                    )
            }

            let accepted = score.value >= minimumScore

            var metadata = example.metadata
            metadata["bootstrap.example_index"] = String(
                exampleIndex
            )
            metadata["bootstrap.objective"] = objective.identifier.rawValue
            metadata["bootstrap.score"] = String(
                score.value
            )
            metadata["bootstrap.teacher_strategy"] = teacher.strategy.rawValue

            let demonstration = AgentInferenceDemonstration(
                input: try jsonValue(
                    example.input
                ),
                output: try jsonValue(
                    execution.output
                ),
                metadata: metadata
            )

            trials.append(
                AgentInferenceDemonstrationBootstrapTrial(
                    exampleIndex: exampleIndex,
                    demonstration: demonstration,
                    score: score,
                    execution: execution.record,
                    accepted: accepted
                )
            )

            if accepted {
                acceptedDemonstrations.append(
                    demonstration
                )
            }
        }

        if !acceptedDemonstrations.isEmpty {
            try insertIdentifier(
                bootstrapIdentifier,
                into: &identifiers
            )

            let bootstrap = AgentInferenceDemonstrationBootstrapRecord(
                inference: inference.definition.identifier,
                objective: objective.identifier,
                teacher: teacher,
                minimumScore: minimumScore,
                trials: trials
            )

            var realization = seed
            realization.demonstrations.append(
                contentsOf: acceptedDemonstrations
            )

            candidates.append(
                AgentInferenceRealizationCandidate(
                    identifier: bootstrapIdentifier,
                    realization: realization,
                    source: .demonstration_bootstrap,
                    bootstrap: bootstrap,
                    metadata: [
                        "bootstrap.accepted": String(
                            acceptedDemonstrations.count
                        ),
                        "bootstrap.attempted": String(
                            trials.count
                        ),
                    ]
                )
            )
        }

        guard !candidates.isEmpty else {
            throw AgentInferenceDemonstrationBootstrapGeneratorError
                .noAcceptedDemonstrations
        }

        return candidates
    }

    private func jsonValue<Value: Encodable>(
        _ value: Value
    ) throws -> JSONValue {
        let data = try JSONEncoder().encode(
            value
        )

        return try JSONDecoder().decode(
            JSONValue.self,
            from: data
        )
    }

    private func insertIdentifier(
        _ identifier: AgentInferenceRealizationCandidateIdentifier,
        into identifiers: inout Set<AgentInferenceRealizationCandidateIdentifier>
    ) throws {
        guard identifiers.insert(identifier).inserted else {
            throw AgentInferenceDemonstrationBootstrapGeneratorError
                .duplicateCandidateIdentifier(
                    identifier
                )
        }
    }
}
