import Agentic
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
        case duplicateSite(InferenceSiteIdentifier)
        case seedBindingUnavailable(InferenceSiteIdentifier)

        public var errorDescription: String? {
            switch self {
            case .noSites:
                return "Program optimization compilation requires at least one inference site."

            case .duplicateSite(let site):
                return "Program optimization compilation contains duplicate inference site '\(site.rawValue)'."

            case .seedBindingUnavailable(let site):
                return "Program optimization compilation seed has no inference binding at site '\(site.rawValue)'."
            }
        }
    }

    struct CompilationSite<ProgramType: Program>:
        Sendable
    {
        public let site: InferenceSiteIdentifier
        public let inference: InferenceIdentifier

        private let seedConfiguration:
            @Sendable (
                ProgramRealization<ProgramType>
            ) -> InferenceRealizationConfiguration?

        private let generateCandidates:
            @Sendable (
                InferenceRealizationConfiguration
            ) async throws -> [InferenceRealizationCandidate]

        private let makeSiteCandidates:
            @Sendable (
                [InferenceRealizationCandidate]
            ) -> SiteCandidates<ProgramType>

        private init(
            site: InferenceSiteIdentifier,
            inference: InferenceIdentifier,
            seedConfiguration:
                @escaping @Sendable (
                    ProgramRealization<ProgramType>
                ) -> InferenceRealizationConfiguration?,
            generateCandidates:
                @escaping @Sendable (
                    InferenceRealizationConfiguration
                ) async throws -> [InferenceRealizationCandidate],
            makeSiteCandidates:
                @escaping @Sendable (
                    [InferenceRealizationCandidate]
                ) -> SiteCandidates<ProgramType>
        ) {
            self.site = site
            self.inference = inference
            self.seedConfiguration = seedConfiguration
            self.generateCandidates = generateCandidates
            self.makeSiteCandidates = makeSiteCandidates
        }

        public static func parse<InferenceType: Inference>(
            _ site: InferenceSite<
                ProgramType,
                InferenceType
            >,
            examples: [InferenceOptimizationExample<InferenceType>],
            generator: any InferenceRealizationCandidateGenerating
        ) throws -> Self {
            let parsedExamples =
                try InferenceOptimizationExamples<InferenceType>.parse(
                    examples
                )

            return Self(
                site: site.identifier,
                inference: site.inference,
                seedConfiguration: { realization in
                    guard
                        let binding = realization.binding(
                            for: site
                        ),
                        binding.inference == site.inference
                    else {
                        return nil
                    }

                    return binding.configuration
                },
                generateCandidates: { seed in
                    try await generator.generate(
                        InferenceType.self,
                        examples: parsedExamples.values,
                        seed: seed
                    )
                },
                makeSiteCandidates: { candidates in
                    SiteCandidates(
                        site,
                        candidates: candidates
                    )
                }
            )
        }

        fileprivate func seedConfiguration(
            in realization: ProgramRealization<ProgramType>
        ) -> InferenceRealizationConfiguration? {
            seedConfiguration(
                realization
            )
        }

        fileprivate func generate(
            seed: InferenceRealizationConfiguration
        ) async throws -> [InferenceRealizationCandidate] {
            try await generateCandidates(
                seed
            )
        }

        fileprivate func siteCandidates(
            _ candidates: [InferenceRealizationCandidate]
        ) -> SiteCandidates<ProgramType> {
            makeSiteCandidates(
                candidates
            )
        }
    }

    struct CompilationPlan<ProgramType: Program>:
        Sendable
    {
        public let seed: ProgramRealization<ProgramType>
        public let sites: [CompilationSite<ProgramType>]

        fileprivate let resolvedSeeds:
            [InferenceSiteIdentifier: InferenceRealizationConfiguration]

        private init(
            seed: ProgramRealization<ProgramType>,
            sites: [CompilationSite<ProgramType>],
            resolvedSeeds:
                [InferenceSiteIdentifier: InferenceRealizationConfiguration]
        ) {
            self.seed = seed
            self.sites = sites
            self.resolvedSeeds = resolvedSeeds
        }

        public static func parse(
            seed: ProgramRealization<ProgramType>,
            sites: [CompilationSite<ProgramType>]
        ) throws -> Self {
            guard !sites.isEmpty else {
                throw CompilationPlanParsingError.noSites
            }

            var seen: Set<InferenceSiteIdentifier> = []
            var resolved:
                [InferenceSiteIdentifier: InferenceRealizationConfiguration] = [:]

            for site in sites {
                guard seen.insert(site.site).inserted else {
                    throw CompilationPlanParsingError.duplicateSite(
                        site.site
                    )
                }

                guard let configuration = site.seedConfiguration(
                    in: seed
                ) else {
                    throw CompilationPlanParsingError
                        .seedBindingUnavailable(
                            site.site
                        )
                }

                resolved[site.site] = configuration
            }

            return Self(
                seed: seed,
                sites: sites,
                resolvedSeeds: resolved
            )
        }

        fileprivate func seedRealization(
            at site: InferenceSiteIdentifier
        ) -> InferenceRealizationConfiguration? {
            resolvedSeeds[site]
        }
    }

    struct CompilationReport<ProgramType: Program>:
        Sendable
    {
        public var selectedRealization: ProgramRealization<ProgramType>
        public var generatedSites: [SiteCandidates<ProgramType>]
        public var optimization: CoordinateReport<ProgramType>

        public init(
            selectedRealization: ProgramRealization<ProgramType>,
            generatedSites: [SiteCandidates<ProgramType>],
            optimization: CoordinateReport<ProgramType>
        ) {
            self.selectedRealization = selectedRealization
            self.generatedSites = generatedSites
            self.optimization = optimization
        }
    }
}

public struct ProgramOptimizationCompiler<ProgramType: Program>:
    Sendable
{
    private let program: ProgramType
    private let inferenceExecutor: any InferenceExecuting
    private let objective: any ProgramOptimization.Objective

    public init(
        program: ProgramType,
        inferenceExecutor: any InferenceExecuting,
        objective: any ProgramOptimization.Objective
    ) {
        self.program = program
        self.inferenceExecutor = inferenceExecutor
        self.objective = objective
    }

    public func compile(
        dataset: ProgramOptimization.Dataset<ProgramType>,
        seed: ProgramRealization<ProgramType>,
        sites: [ProgramOptimization.CompilationSite<ProgramType>],
        maximumPasses: Int = 4
    ) async throws -> ProgramOptimization.CompilationReport<ProgramType> {
        let plan = try ProgramOptimization
            .CompilationPlan<ProgramType>
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
        dataset: ProgramOptimization.Dataset<ProgramType>,
        plan: ProgramOptimization.CompilationPlan<ProgramType>,
        passLimit: ProgramOptimization.CoordinatePassLimit = .standard
    ) async throws -> ProgramOptimization.CompilationReport<ProgramType> {
        var generatedSites: [
            ProgramOptimization.SiteCandidates<ProgramType>
        ] = []

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

            let candidates = try await site.generate(
                seed: seed
            )
            generatedSites.append(
                site.siteCandidates(
                    candidates
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
