import Agentic
import TestFlows

@main
enum OptimizerTestMain {
    static func main() async {
        await TestFlowCLI.run(
            suite: OptimizerFlowSuite.self
        )
    }
}

enum OptimizerFlowSuite: TestFlowRegistry {
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
            try await OptimizerFlowTesting
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
            try await OptimizerFlowTesting
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
            try await OptimizerFlowTesting
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
            try await OptimizerFlowTesting
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
            try await OptimizerFlowTesting
                .runDemonstrationBootstrap()
        },
        TestFlow(
            "program-realization-optimization",
            tags: [
                "agentic-optimizer",
                "program",
                "optimization",
                "realization",
                "inference-sites",
                "search",
            ]
        ) {
            try await OptimizerFlowTesting
                .runProgramRealizationOptimization()
        },
        TestFlow(
            "program-candidate-generation",
            tags: [
                "agentic-optimizer",
                "program",
                "optimization",
                "generation",
                "inference-sites",
                "bounded",
                "provenance",
            ]
        ) {
            try await OptimizerFlowTesting
                .runProgramCandidateGeneration()
        },
        TestFlow(
            "optimization-input-parsing",
            tags: [
                "agentic-optimizer",
                "optimization",
                "parsing",
                "codable",
                "score",
                "problem",
            ]
        ) {
            try await OptimizerFlowTesting
                .runOptimizationInputParsing()
        },
        TestFlow(
            "program-coordinate-optimization",
            tags: [
                "agentic-optimizer",
                "program",
                "optimization",
                "coordinate",
                "inference-sites",
                "bounded",
                "convergence",
                "provenance",
            ]
        ) {
            try await OptimizerFlowTesting
                .runProgramCoordinateOptimization()
        },
        TestFlow(
            "optimization-held-out-evaluation",
            tags: [
                "agentic-optimizer",
                "optimization",
                "training",
                "evaluation",
                "held-out",
                "inference",
                "program",
                "coordinate",
            ]
        ) {
            try await OptimizerFlowTesting
                .runHeldOutEvaluation()
        },
        TestFlow(
            "multi-objective-optimization",
            tags: [
                "agentic-optimizer",
                "optimization",
                "multi-objective",
                "quality",
                "tokens",
                "cost",
                "latency",
                "inference",
                "program",
            ]
        ) {
            try await OptimizerFlowTesting
                .runMultiObjectiveOptimization()
        },
        TestFlow(
            "program-optimization-compiler",
            tags: [
                "agentic-optimizer",
                "program",
                "optimization",
                "compiler",
                "candidate-generation",
                "coordinate",
                "held-out",
                "provenance",
            ]
        ) {
            try await OptimizerFlowTesting
                .runProgramOptimizationCompiler()
        },
    ]
}