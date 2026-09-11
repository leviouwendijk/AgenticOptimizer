import TestFlows

@main
enum AgenticOptimizerTestMain {
    static func main() async {
        await TestFlowCLI.run(
            suite: AgenticOptimizerFlowSuite.self
        )
    }
}

enum AgenticOptimizerFlowSuite: TestFlowRegistry {
    static let title = "AgenticOptimizer flow tests"

    static let flows: [TestFlow] = [
        TestFlow(
            "inference-realization-search",
            tags: [
                "agentic-optimizer",
                "inference",
                "realization",
                "search",
                "objective",
            ]
        ) {
            try await AgenticOptimizerFlowTesting
                .runInferenceRealizationSearch()
        },
        TestFlow(
            "instruction-candidate-generation",
            tags: [
                "agentic-optimizer",
                "inference",
                "realization",
                "generation",
                "instructions",
                "search",
            ]
        ) {
            try await AgenticOptimizerFlowTesting
                .runInstructionCandidateGeneration()
        },
        TestFlow(
            "inference-instruction-proposal",
            tags: [
                "agentic-optimizer",
                "inference",
                "optimization",
                "generation",
                "proposal",
                "instructions",
            ]
        ) {
            try await AgenticOptimizerFlowTesting
                .runInferenceInstructionProposal()
        },
        TestFlow(
            "demonstration-optimization",
            tags: [
                "agentic-optimizer",
                "inference",
                "optimization",
                "demonstrations",
                "few-shot",
                "search",
            ]
        ) {
            try await AgenticOptimizerFlowTesting
                .runDemonstrationOptimization()
        },
        TestFlow(
            "demonstration-bootstrap",
            tags: [
                "agentic-optimizer",
                "inference",
                "optimization",
                "demonstrations",
                "bootstrap",
                "teacher",
            ]
        ) {
            try await AgenticOptimizerFlowTesting
                .runDemonstrationBootstrap()
        },
    ]
}
