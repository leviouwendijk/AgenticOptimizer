import AgenticInference

public protocol AgentInferenceRealizationCandidateGenerating: Sendable {
    func generate<Inference: AgentInference>(
        _ inference: Inference.Type,
        examples: [AgentInferenceOptimizationExample<Inference>],
        seed: AgentInferenceRealization
    ) async throws -> [AgentInferenceRealizationCandidate]
}
