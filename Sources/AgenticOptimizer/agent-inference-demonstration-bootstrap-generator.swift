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
    case duplicateCandidateIdentifier(
        AgentInferenceRealizationCandidateIdentifier
    )
    case noAcceptedDemonstrations

    public var errorDescription: String? {
        switch self {
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

    public let teacher: AgentInferenceRealization
    public let minimumScore: AgentInferenceOptimizationScore
    public let includeSeed: Bool
    public let seedIdentifier: AgentInferenceRealizationCandidateIdentifier
    public let bootstrapIdentifier: AgentInferenceRealizationCandidateIdentifier

    private init(
        executor: any AgentInferenceExecuting,
        objective: any AgentInferenceOptimizationObjective,
        teacher: AgentInferenceRealization,
        parsedMinimumScore minimumScore: AgentInferenceOptimizationScore,
        includeSeed: Bool,
        seedIdentifier: AgentInferenceRealizationCandidateIdentifier,
        bootstrapIdentifier: AgentInferenceRealizationCandidateIdentifier
    ) {
        self.executor = executor
        self.objective = objective
        self.teacher = teacher
        self.minimumScore = minimumScore
        self.includeSeed = includeSeed
        self.seedIdentifier = seedIdentifier
        self.bootstrapIdentifier = bootstrapIdentifier
    }

    public static func parse(
        executor: any AgentInferenceExecuting,
        objective: any AgentInferenceOptimizationObjective,
        teacher: AgentInferenceRealization,
        minimumScore: Double,
        includeSeed: Bool = true,
        seedIdentifier: AgentInferenceRealizationCandidateIdentifier = "seed",
        bootstrapIdentifier: AgentInferenceRealizationCandidateIdentifier = "bootstrapped"
    ) throws -> Self {
        let parsedMinimumScore = try AgentInferenceOptimizationScore(
            value: minimumScore
        )

        if includeSeed && seedIdentifier == bootstrapIdentifier {
            throw AgentInferenceDemonstrationBootstrapGeneratorError
                .duplicateCandidateIdentifier(
                    seedIdentifier
                )
        }

        return Self(
            executor: executor,
            objective: objective,
            teacher: teacher,
            parsedMinimumScore: parsedMinimumScore,
            includeSeed: includeSeed,
            seedIdentifier: seedIdentifier,
            bootstrapIdentifier: bootstrapIdentifier
        )
    }

    public func generate<Inference: AgentInference>(
        _ inference: Inference.Type,
        examples: [AgentInferenceOptimizationExample<Inference>],
        seed: AgentInferenceRealization
    ) async throws -> [AgentInferenceRealizationCandidate] {
        var candidates: [AgentInferenceRealizationCandidate] = []

        if includeSeed {
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
            let accepted = score.value >= minimumScore.value

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
            let bootstrap = AgentInferenceDemonstrationBootstrapRecord(
                inference: inference.definition.identifier,
                objective: objective.identifier,
                teacher: teacher,
                minimumScore: minimumScore.value,
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
}
