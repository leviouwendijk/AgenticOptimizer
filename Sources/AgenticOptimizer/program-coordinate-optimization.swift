import Agentic
import AgenticInference
import AgenticPrograms
import Foundation

public extension ProgramOptimization {
    enum CoordinatePassLimitError:
        Error,
        Sendable,
        LocalizedError
    {
        case nonPositive(Int)

        public var errorDescription: String? {
            switch self {
            case .nonPositive(let value):
                return "Program coordinate optimization pass limit must be positive; received \(value)."
            }
        }
    }

    struct CoordinatePassLimit:
        Sendable,
        Codable,
        Hashable
    {
        public let value: Int

        private enum CodingKeys: String, CodingKey {
            case value
        }

        private init(
            parsed value: Int
        ) {
            self.value = value
        }

        public static let standard = Self(
            parsed: 4
        )

        public static func parse(
            _ value: Int
        ) throws -> Self {
            guard value > 0 else {
                throw CoordinatePassLimitError.nonPositive(
                    value
                )
            }

            return Self(
                parsed: value
            )
        }

        public init(
            from decoder: Decoder
        ) throws {
            let container = try decoder.container(
                keyedBy: CodingKeys.self
            )

            self = try Self.parse(
                try container.decode(
                    Int.self,
                    forKey: .value
                )
            )
        }

        public func encode(
            to encoder: Encoder
        ) throws {
            var container = encoder.container(
                keyedBy: CodingKeys.self
            )

            try container.encode(
                value,
                forKey: .value
            )
        }
    }

    struct CoordinateDecision:
        Sendable
    {
        public var pass: Int
        public var siteIndex: Int
        public var site: InferenceSiteIdentifier
        public var before: InferenceOptimizationScore
        public var after: InferenceOptimizationScore
        public var selection: SiteSelection?
        public var trialIndexes: [Int]

        public var accepted: Bool {
            selection != nil
        }

        public init(
            pass: Int,
            siteIndex: Int,
            site: InferenceSiteIdentifier,
            before: InferenceOptimizationScore,
            after: InferenceOptimizationScore,
            selection: SiteSelection?,
            trialIndexes: [Int]
        ) {
            self.pass = pass
            self.siteIndex = siteIndex
            self.site = site
            self.before = before
            self.after = after
            self.selection = selection
            self.trialIndexes = trialIndexes
        }
    }

    struct CoordinateResult<ProgramType: Program>:
        Sendable
    {
        public var objective: ObjectiveID
        public var selected: Candidate<ProgramType>
        public var score: InferenceOptimizationScore
        public var passesCompleted: Int
        public var decisions: [CoordinateDecision]
        public var trials: [Trial]
        public var converged: Bool

        public init(
            objective: ObjectiveID,
            selected: Candidate<ProgramType>,
            score: InferenceOptimizationScore,
            passesCompleted: Int,
            decisions: [CoordinateDecision],
            trials: [Trial],
            converged: Bool
        ) {
            self.objective = objective
            self.selected = selected
            self.score = score
            self.passesCompleted = passesCompleted
            self.decisions = decisions
            self.trials = trials
            self.converged = converged
        }
    }
}