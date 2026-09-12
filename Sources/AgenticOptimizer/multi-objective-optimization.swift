import AgenticInference
import Foundation

public enum AgentOptimizationMetric:
    String,
    Sendable,
    Codable,
    Hashable
{
    case quality
    case total_tokens
    case estimated_usd
    case latency_seconds
}

public enum AgentOptimizationResourceMetricsParsingError:
    Error,
    Sendable,
    LocalizedError
{
    case negativeTotalTokens(Int)
    case invalidEstimatedUsd(Double)
    case invalidLatencySeconds(Double)

    public var errorDescription: String? {
        switch self {
        case .negativeTotalTokens(let value):
            return "Optimization token usage must be non-negative; received \(value)."

        case .invalidEstimatedUsd(let value):
            return "Optimization estimated USD must be finite and non-negative; received \(value)."

        case .invalidLatencySeconds(let value):
            return "Optimization latency must be finite and non-negative; received \(value)."
        }
    }
}

public struct AgentOptimizationResourceMetrics:
    Sendable,
    Codable,
    Hashable
{
    public let totalTokens: Int?
    public let estimatedUsd: Double?
    public let latencySeconds: Double?

    private init(
        parsedTotalTokens totalTokens: Int?,
        estimatedUsd: Double?,
        latencySeconds: Double?
    ) {
        self.totalTokens = totalTokens
        self.estimatedUsd = estimatedUsd
        self.latencySeconds = latencySeconds
    }

    public static func parse(
        totalTokens: Int? = nil,
        estimatedUsd: Double? = nil,
        latencySeconds: Double? = nil
    ) throws -> Self {
        if let totalTokens, totalTokens < 0 {
            throw AgentOptimizationResourceMetricsParsingError
                .negativeTotalTokens(
                    totalTokens
                )
        }

        if let estimatedUsd,
           !estimatedUsd.isFinite || estimatedUsd < 0
        {
            throw AgentOptimizationResourceMetricsParsingError
                .invalidEstimatedUsd(
                    estimatedUsd
                )
        }

        if let latencySeconds,
           !latencySeconds.isFinite || latencySeconds < 0
        {
            throw AgentOptimizationResourceMetricsParsingError
                .invalidLatencySeconds(
                    latencySeconds
                )
        }

        return Self(
            parsedTotalTokens: totalTokens,
            estimatedUsd: estimatedUsd,
            latencySeconds: latencySeconds
        )
    }
}

public protocol AgentOptimizationResourceEstimating:
    Sendable
{
    func estimate(
        executions: [AgentInferenceExecutionRecord],
        measuredDurationSeconds: Double
    ) throws -> AgentOptimizationResourceMetrics
}

public struct AgentOptimizationExecutionResourceEstimator:
    AgentOptimizationResourceEstimating,
    Sendable
{
    public init() {}

    public func estimate(
        executions: [AgentInferenceExecutionRecord],
        measuredDurationSeconds: Double
    ) throws -> AgentOptimizationResourceMetrics {
        var totalTokens = 0
        var tokenUsageAvailable = true

        for execution in executions {
            for attempt in execution.attempts {
                guard let usage = attempt.usage else {
                    tokenUsageAvailable = false
                    continue
                }

                if let total = usage.totalTokens {
                    totalTokens += total
                } else if let input = usage.inputTokens,
                          let output = usage.outputTokens
                {
                    totalTokens += input + output
                } else {
                    tokenUsageAvailable = false
                }
            }
        }

        return try AgentOptimizationResourceMetrics.parse(
            totalTokens:
                tokenUsageAvailable
                ? totalTokens
                : nil,
            estimatedUsd: nil,
            latencySeconds: measuredDurationSeconds
        )
    }
}

public enum AgentOptimizationMultiObjectiveWeightsParsingError:
    Error,
    Sendable,
    LocalizedError
{
    case invalidWeight(
        metric: AgentOptimizationMetric,
        value: Double
    )
    case noWeightedMetrics

    public var errorDescription: String? {
        switch self {
        case .invalidWeight(
            let metric,
            let value
        ):
            return "Optimization weight '\(metric.rawValue)' must be finite and non-negative; received \(value)."

        case .noWeightedMetrics:
            return "Multi-objective optimization requires at least one positive metric weight."
        }
    }
}

public struct AgentOptimizationMultiObjectiveWeights:
    Sendable,
    Codable,
    Hashable
{
    public let quality: Double
    public let totalTokens: Double
    public let estimatedUsd: Double
    public let latencySeconds: Double

    private init(
        parsedQuality quality: Double,
        totalTokens: Double,
        estimatedUsd: Double,
        latencySeconds: Double
    ) {
        self.quality = quality
        self.totalTokens = totalTokens
        self.estimatedUsd = estimatedUsd
        self.latencySeconds = latencySeconds
    }

    public static let qualityOnly = Self(
        parsedQuality: 1,
        totalTokens: 0,
        estimatedUsd: 0,
        latencySeconds: 0
    )

    public static func parse(
        quality: Double,
        totalTokens: Double = 0,
        estimatedUsd: Double = 0,
        latencySeconds: Double = 0
    ) throws -> Self {
        let values: [
            (
                metric: AgentOptimizationMetric,
                value: Double
            )
        ] = [
            (
                .quality,
                quality
            ),
            (
                .total_tokens,
                totalTokens
            ),
            (
                .estimated_usd,
                estimatedUsd
            ),
            (
                .latency_seconds,
                latencySeconds
            ),
        ]

        for entry in values {
            guard entry.value.isFinite,
                  entry.value >= 0
            else {
                throw AgentOptimizationMultiObjectiveWeightsParsingError
                    .invalidWeight(
                        metric: entry.metric,
                        value: entry.value
                    )
            }
        }

        guard values.contains(
            where: {
                $0.value > 0
            }
        ) else {
            throw AgentOptimizationMultiObjectiveWeightsParsingError
                .noWeightedMetrics
        }

        return Self(
            parsedQuality: quality,
            totalTokens: totalTokens,
            estimatedUsd: estimatedUsd,
            latencySeconds: latencySeconds
        )
    }

    public var total: Double {
        quality
            + totalTokens
            + estimatedUsd
            + latencySeconds
    }
}

public struct AgentOptimizationMultiObjectiveMeasurement:
    Sendable,
    Codable,
    Hashable
{
    public var quality: AgentInferenceOptimizationScore
    public var resources: AgentOptimizationResourceMetrics

    public init(
        quality: AgentInferenceOptimizationScore,
        resources: AgentOptimizationResourceMetrics
    ) {
        self.quality = quality
        self.resources = resources
    }
}

public enum AgentOptimizationMultiObjectiveRankingError:
    Error,
    Sendable,
    LocalizedError
{
    case noCandidates
    case metricUnavailable(
        AgentOptimizationMetric
    )

    public var errorDescription: String? {
        switch self {
        case .noCandidates:
            return "Multi-objective optimization requires at least one candidate."

        case .metricUnavailable(let metric):
            return "Multi-objective metric '\(metric.rawValue)' is weighted but unavailable for at least one candidate."
        }
    }
}

public struct AgentOptimizationMultiObjectiveRanking:
    Sendable
{
    public var utilities: [AgentInferenceOptimizationScore]
    public var selectedIndex: Int

    public init(
        utilities: [AgentInferenceOptimizationScore],
        selectedIndex: Int
    ) {
        self.utilities = utilities
        self.selectedIndex = selectedIndex
    }

    public static func rank(
        _ measurements: [AgentOptimizationMultiObjectiveMeasurement],
        weights: AgentOptimizationMultiObjectiveWeights
    ) throws -> Self {
        guard !measurements.isEmpty else {
            throw AgentOptimizationMultiObjectiveRankingError
                .noCandidates
        }

        let quality = measurements.map {
            $0.quality.value
        }
        let tokens = try values(
            measurements.map {
                $0.resources.totalTokens.map(
                    Double.init
                )
            },
            metric: .total_tokens,
            weight: weights.totalTokens
        )
        let cost = try values(
            measurements.map {
                $0.resources.estimatedUsd
            },
            metric: .estimated_usd,
            weight: weights.estimatedUsd
        )
        let latency = try values(
            measurements.map {
                $0.resources.latencySeconds
            },
            metric: .latency_seconds,
            weight: weights.latencySeconds
        )

        let normalizedQuality = normalized(
            quality,
            maximizing: true
        )
        let normalizedTokens = tokens.map {
            normalized(
                $0,
                maximizing: false
            )
        }
        let normalizedCost = cost.map {
            normalized(
                $0,
                maximizing: false
            )
        }
        let normalizedLatency = latency.map {
            normalized(
                $0,
                maximizing: false
            )
        }

        var utilities: [AgentInferenceOptimizationScore] = []

        for index in measurements.indices {
            var value =
                normalizedQuality[index]
                * weights.quality

            if let normalizedTokens {
                value +=
                    normalizedTokens[index]
                    * weights.totalTokens
            }

            if let normalizedCost {
                value +=
                    normalizedCost[index]
                    * weights.estimatedUsd
            }

            if let normalizedLatency {
                value +=
                    normalizedLatency[index]
                    * weights.latencySeconds
            }

            utilities.append(
                try AgentInferenceOptimizationScore(
                    value: value / weights.total
                )
            )
        }

        var selectedIndex = 0

        for index in utilities.indices.dropFirst() {
            if utilities[index].value
                > utilities[selectedIndex].value
            {
                selectedIndex = index
            }
        }

        return Self(
            utilities: utilities,
            selectedIndex: selectedIndex
        )
    }

    public static func aggregate(
        _ metrics: [AgentOptimizationResourceMetrics]
    ) throws -> AgentOptimizationResourceMetrics {
        var totalTokens = 0
        var estimatedUsd = 0.0
        var latencySeconds = 0.0
        var tokensAvailable = true
        var costAvailable = true
        var latencyAvailable = true

        for metric in metrics {
            if let value = metric.totalTokens {
                totalTokens += value
            } else {
                tokensAvailable = false
            }

            if let value = metric.estimatedUsd {
                estimatedUsd += value
            } else {
                costAvailable = false
            }

            if let value = metric.latencySeconds {
                latencySeconds += value
            } else {
                latencyAvailable = false
            }
        }

        return try AgentOptimizationResourceMetrics.parse(
            totalTokens:
                tokensAvailable
                ? totalTokens
                : nil,
            estimatedUsd:
                costAvailable
                ? estimatedUsd
                : nil,
            latencySeconds:
                latencyAvailable
                ? latencySeconds
                : nil
        )
    }

    private static func values(
        _ values: [Double?],
        metric: AgentOptimizationMetric,
        weight: Double
    ) throws -> [Double]? {
        guard weight > 0 else {
            return nil
        }

        var parsed: [Double] = []

        for value in values {
            guard let value else {
                throw AgentOptimizationMultiObjectiveRankingError
                    .metricUnavailable(
                        metric
                    )
            }

            parsed.append(
                value
            )
        }

        return parsed
    }

    private static func normalized(
        _ values: [Double],
        maximizing: Bool
    ) -> [Double] {
        guard let minimum = values.min(),
              let maximum = values.max()
        else {
            return []
        }

        let range = maximum - minimum

        guard range > 0 else {
            return Array(
                repeating: 1,
                count: values.count
            )
        }

        return values.map { value in
            if maximizing {
                return (value - minimum) / range
            }

            return (maximum - value) / range
        }
    }
}
