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
    ]
}
