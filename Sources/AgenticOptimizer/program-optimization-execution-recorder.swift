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

    func execute(
        _ invocation: InferenceInvocation
    ) async throws -> InferenceInvocationResult {
        let result = try await base.execute(
            invocation
        )

        await recorder.record(
            result.record
        )

        return result
    }
}