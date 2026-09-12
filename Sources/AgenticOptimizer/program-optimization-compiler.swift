import AgenticInference
import AgenticPrograms
import Foundation

public extension ProgramOptimization {
    enum CompilationPlanParsingError:
        Error,
        Sendable,
        LocalizedError
    {
        case noSites
        case duplicateSite(AgentInferenceSiteIdentifier)
        case seedBindingUnavailable(AgentInferenceSiteIdentifier)
        case inferenceMismatch(
            site: AgentInferenceSiteIdentifier,
            seed: AgentInferenceIdentifier,
            compilation: AgentInferenceIdentifier
        )

        public var errorDescription: String? {
            switch self {
            case .noSites:
                return "Program optimization compilation requires at least one inference site."

            case .duplicateSite(let site):
                return "Program optimization compilation contains duplicate inference site '\(site.rawValue)'."

            case .seedBindingUnavailable(let site):
                return "Program optimization compilation seed has no inference binding at site '\(site.rawValue)'."

            case .inferenceMismatch(
                let site,
                let seed,
                let compilation
            ):
                return "Program optimization compilation site '\(site.rawValue)' is bound to '\(seed.rawValue)' in the seed realization but the compilation site targets '\(compilation.rawValue)'."
            }
        }
    }

    struct CompilationSite<Program: AgentProgram>:
        Sendable
    {
        public let site: AgentInferenceSiteIdentifier
        public let inference: AgentInferenceIdentifier

        private let generateCandidates:
            @Sendable (
                AgentInferenceRealization
            ) async throws -> [AgentInferenceRealizationCandidate]

        private init(
            site: AgentInferenceSiteIdentifier,
            inference: AgentInferenceIdentifier,
            generateCandidates:
                @escaping @Sendable (
                    AgentInferenceRealization
                ) async throws -> [AgentInferenceRealizationCandidate]
        ) {
            self.site = site
            self.inference = inference
            self.generateCandidates = generateCandidates
        }

        public static func parse<Inference: AgentInference>(
            _ inference: Inference.Type,
            at site: AgentInferenceSiteIdentifier,
            examples: [AgentInferenceOptimizationExample<Inference>],
            generator: any AgentInferenceRealizationCandidateGenerating
        ) throws -> Self {
            let parsedExamples =
                try AgentInferenceOptimizationExamples<Inference>.parse(
                    examples
                )

            return Self(
                site: site,
                inference: inference.definition.identifier,
                generateCandidates: { seed in
                    try await generator.generate(
                        inference,
                        examples: parsedExamples.values,
                        seed: seed
                    )
                }
            )
        }

        fileprivate func generate(
            seed: AgentInferenceRealization
        ) async throws -> [AgentInferenceRealizationCandidate] {
            try await generateCandidates(
                seed
            )
        }
    }

    struct CompilationPlan<Program: AgentProgram>:
        Sendable
    {
        public let seed: AgentProgramRealization<Program>
        public let sites: [CompilationSite<Program>]

        fileprivate let resolvedSeeds:
            [AgentInferenceSiteIdentifier: AgentInferenceRealization]

        private init(
            seed: AgentProgramRealization<Program>,
            sites: [CompilationSite<Program>],
            resolvedSeeds:
                [AgentInferenceSiteIdentifier: AgentInferenceRealization]
        ) {
            self.seed = seed
            self.sites = sites
            self.resolvedSeeds = resolvedSeeds
        }

        public static func parse(
            seed: AgentProgramRealization<Program>,
            sites: [CompilationSite<Program>]
        ) throws -> Self {
            guard !sites.isEmpty else {
                throw CompilationPlanParsingError.noSites
            }

            var seen: Set<AgentInferenceSiteIdentifier> = []
            var resolved:
                [AgentInferenceSiteIdentifier: AgentInferenceRealization] = [:]

            for site in sites {
                guard seen.insert(site.site).inserted else {
                    throw CompilationPlanParsingError.duplicateSite(
                        site.site
                    )
                }

                guard let binding = seed.inference(
                    at: site.site
                ) else {
                    throw CompilationPlanParsingError
                        .seedBindingUnavailable(
                            site.site
                        )
                }

                guard binding.inference == site.inference else {
                    throw CompilationPlanParsingError.inferenceMismatch(
                        site: site.site,
                        seed: binding.inference,
                        compilation: site.inference
                    )
                }

                resolved[site.site] = binding.realization
            }

            return Self(
                seed: seed,
                sites: sites,
                resolvedSeeds: resolved
            )
        }

        fileprivate func seedRealization(
            at site: AgentInferenceSiteIdentifier
        ) -> AgentInferenceRealization? {
            resolvedSeeds[site]
        }
    }

    struct CompilationReport<Program: AgentProgram>:
        Sendable
    {
        public var selectedRealization: AgentProgramRealization<Program>
        public var generatedSites: [SiteCandidates]
        public var optimization: CoordinateReport<Program>

        public init(
            selectedRealization: AgentProgramRealization<Program>,
            generatedSites: [SiteCandidates],
            optimization: CoordinateReport<Program>
        ) {
            self.selectedRealization = selectedRealization
            self.generatedSites = generatedSites
            self.optimization = optimization
        }
    }
}

public struct ProgramOptimizationCompiler<Program: AgentProgram>:
    Sendable
{
    private let program: Program
    private let inferenceExecutor: any AgentInferenceExecuting
    private let objective: any ProgramOptimization.Objective

    public init(
        program: Program,
        inferenceExecutor: any AgentInferenceExecuting,
        objective: any ProgramOptimization.Objective
    ) {
        self.program = program
        self.inferenceExecutor = inferenceExecutor
        self.objective = objective
    }

    public func compile(
        dataset: ProgramOptimization.Dataset<Program>,
        seed: AgentProgramRealization<Program>,
        sites: [ProgramOptimization.CompilationSite<Program>],
        maximumPasses: Int = 4
    ) async throws -> ProgramOptimization.CompilationReport<Program> {
        let plan = try ProgramOptimization
            .CompilationPlan<Program>
            .parse(
                seed: seed,
                sites: sites
            )
        let passLimit = try ProgramOptimization
            .CoordinatePassLimit
            .parse(
                maximumPasses
            )

        return try await compile(
            dataset: dataset,
            plan: plan,
            passLimit: passLimit
        )
    }

    public func compile(
        dataset: ProgramOptimization.Dataset<Program>,
        plan: ProgramOptimization.CompilationPlan<Program>,
        passLimit: ProgramOptimization.CoordinatePassLimit = .standard
    ) async throws -> ProgramOptimization.CompilationReport<Program> {
        var generatedSites: [ProgramOptimization.SiteCandidates] = []

        for site in plan.sites {
            guard let seed = plan.seedRealization(
                at: site.site
            ) else {
                throw ProgramOptimization
                    .CompilationPlanParsingError
                    .seedBindingUnavailable(
                        site.site
                    )
            }

            generatedSites.append(
                ProgramOptimization.SiteCandidates(
                    site: site.site,
                    inference: site.inference,
                    candidates: try await site.generate(
                        seed: seed
                    )
                )
            )
        }

        let optimizer = ProgramCoordinateOptimizer(
            program: program,
            inferenceExecutor: inferenceExecutor,
            objective: objective
        )
        let optimization = try await optimizer.optimize(
            dataset: dataset,
            seed: plan.seed,
            sites: generatedSites,
            maximumPasses: passLimit.value
        )

        return ProgramOptimization.CompilationReport(
            selectedRealization:
                optimization.optimization.selected.realization,
            generatedSites: generatedSites,
            optimization: optimization
        )
    }
}
