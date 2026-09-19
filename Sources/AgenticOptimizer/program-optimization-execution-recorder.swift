import Agentic
import AgenticInference

actor ProgramOptimizationExecutionRecorder {
    private var records: [InferenceExecutionRecord] = []

    func record(
        _ record: InferenceExecutionRecord
    ) {
        records.append(
            record
        )
    }

    func snapshot() -> [InferenceExecutionRecord] {
        records
    }
}

struct ProgramOptimizationRecordingInferenceExecutor:
    InferenceExecuting,
    Sendable
{
    let base: any InferenceExecuting
    let recorder: ProgramOptimizationExecutionRecorder

    func execute<InferenceType: Inference>(
        _ inference: InferenceType.Type,
        input: InferenceType.Input,
        realization: InferenceRealizationConfiguration,
        context: InferenceExecutionContext
    ) async throws -> InferenceExecutionResult<InferenceType.Output> {
        _ = context
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