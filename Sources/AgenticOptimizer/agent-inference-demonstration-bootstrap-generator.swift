import Agentic
import AgenticInference
import Foundation
import Primitives

public struct InferenceDemonstrationBootstrapTrial:
    Sendable,
    Codable,
    Hashable
{
    public var exampleIndex: Int
    public var demonstration: InferenceDemonstration
    public var score: InferenceOptimizationScore
    public var execution: InferenceExecutionRecord
    public var accepted: Bool

    public init(
        exampleIndex: Int,
        demonstration: InferenceDemonstration,
        score: InferenceOptimizationScore,
        execution: InferenceExecutionRecord,
        accepted: Bool
    ) {
        self.exampleIndex = exampleIndex
        self.demonstration = demonstration
        self.score = score
        self.execution = execution
        self.accepted = accepted
    }
}

public struct InferenceDemonstrationBootstrapRecord:
    Sendable,
    Codable,
    Hashable
{
    public var inference: InferenceIdentifier
    public var objective: InferenceOptimizationObjectiveIdentifier
    public var teacher: InferenceRealizationConfiguration
    public var minimumScore: Double
    public var trials: [InferenceDemonstrationBootstrapTrial]

    public init(
        inference: InferenceIdentifier,
        objective: InferenceOptimizationObjectiveIdentifier,
        teacher: InferenceRealizationConfiguration,
        minimumScore: Double,
        trials: [InferenceDemonstrationBootstrapTrial]
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

public enum InferenceDemonstrationBootstrapGeneratorError:
    Error,
    Sendable,
    LocalizedError
{
    case duplicateCandidateIdentifier(
        InferenceRealizationCandidateIdentifier
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

public struct InferenceDemonstrationBootstrapGenerator:
    InferenceRealizationCandidateGenerating,
    Sendable
{
    private let executor: any InferenceExecuting
    private let objective: any InferenceOptimizationObjective

    public let teacher: InferenceRealizationConfiguration
    public let minimumScore: InferenceOptimizationScore
    public let includeSeed: Bool
    public let seedIdentifier: InferenceRealizationCandidateIdentifier
    public let bootstrapIdentifier: InferenceRealizationCandidateIdentifier

    private init(
        executor: any InferenceExecuting,
        objective: any InferenceOptimizationObjective,
        teacher: InferenceRealizationConfiguration,
        parsedMinimumScore minimumScore: InferenceOptimizationScore,
        includeSeed: Bool,
        seedIdentifier: InferenceRealizationCandidateIdentifier,
        bootstrapIdentifier: InferenceRealizationCandidateIdentifier
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
        executor: any InferenceExecuting,
        objective: any InferenceOptimizationObjective,
        teacher: InferenceRealizationConfiguration,
        minimumScore: Double,
        includeSeed: Bool = true,
        seedIdentifier: InferenceRealizationCandidateIdentifier = "seed",
        bootstrapIdentifier: InferenceRealizationCandidateIdentifier = "bootstrapped"
    ) throws -> Self {
        let parsedMinimumScore = try InferenceOptimizationScore(
            value: minimumScore
        )

        if includeSeed && seedIdentifier == bootstrapIdentifier {
            throw InferenceDemonstrationBootstrapGeneratorError
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

    public func generate<InferenceType: Inference>(
        _ inference: InferenceType.Type,
        examples: [InferenceOptimizationExample<InferenceType>],
        seed: InferenceRealizationConfiguration
    ) async throws -> [InferenceRealizationCandidate] {
        var candidates: [InferenceRealizationCandidate] = []

        if includeSeed {
            candidates.append(
                InferenceRealizationCandidate(
                    identifier: seedIdentifier,
                    realization: seed,
                    source: .seed
                )
            )
        }

        var acceptedDemonstrations: [InferenceDemonstration] = []
        var trials: [InferenceDemonstrationBootstrapTrial] = []

        for (exampleIndex, example) in examples.enumerated() {
            let execution = try await InferenceType.execute(
                using: executor,
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

            let demonstration = InferenceDemonstration(
                input: try jsonValue(
                    example.input
                ),
                output: try jsonValue(
                    execution.output
                ),
                metadata: metadata
            )

            trials.append(
                InferenceDemonstrationBootstrapTrial(
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
            let bootstrap = InferenceDemonstrationBootstrapRecord(
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
                InferenceRealizationCandidate(
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
            throw InferenceDemonstrationBootstrapGeneratorError
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