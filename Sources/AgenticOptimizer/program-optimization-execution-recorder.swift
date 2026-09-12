import AgenticInference

actor ProgramOptimizationExecutionRecorder {
    private var records: [AgentInferenceExecutionRecord] = []

    func record(
        _ record: AgentInferenceExecutionRecord
    ) {
        records.append(
            record
        )
    }

    func snapshot() -> [AgentInferenceExecutionRecord] {
        records
    }
}

struct ProgramOptimizationRecordingInferenceExecutor:
    AgentInferenceExecuting,
    Sendable
{
    let base: any AgentInferenceExecuting
    let recorder: ProgramOptimizationExecutionRecorder

    func execute<Inference: AgentInference>(
        _ inference: Inference.Type,
        input: Inference.Input,
        realization: AgentInferenceRealization
    ) async throws -> AgentInferenceExecutionResult<Inference.Output> {
        let result = try await base.execute(
            inference,
            input: input,
            realization: realization
        )

        await recorder.record(
            result.record
        )

        return result
    }
}
