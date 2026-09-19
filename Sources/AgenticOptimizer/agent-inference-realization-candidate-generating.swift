import Agentic
import AgenticInference

public protocol InferenceRealizationCandidateGenerating: Sendable {
    func generate<InferenceType: Inference>(
        _ inference: InferenceType.Type,
        examples: [InferenceOptimizationExample<InferenceType>],
        seed: InferenceRealizationConfiguration
    ) async throws -> [InferenceRealizationCandidate]
}