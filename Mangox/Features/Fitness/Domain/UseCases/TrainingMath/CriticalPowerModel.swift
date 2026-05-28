// Features/Fitness/Domain/UseCases/TrainingMath/CriticalPowerModel.swift
import Foundation

/// Two-parameter critical power model: P(t) = CP + W′/t (power in W, duration t in s, W′ in J).
nonisolated enum CriticalPowerModel {

    struct Fit: Sendable, Equatable {
        let criticalPowerWatts: Int
        let wPrimeJoules: Int
        /// Coefficient of determination for the linearized fit (0…1).
        let rSquared: Double
        let sampleCount: Int

        var plainLanguageSummary: String {
            String(
                format: "CP %dW, W′ %dkJ (fit from %d durations, R² %.2f)",
                criticalPowerWatts,
                wPrimeJoules / 1000,
                sampleCount,
                rSquared
            )
        }
    }

    /// Ignore very short efforts dominated by neuromuscular power.
    nonisolated static let defaultMinDurationSeconds = 180

    /// Fits CP and W′ from mean-maximal power points using P = CP + W′·(1/t).
    nonisolated static func fit(
        from points: [PowerCurveAnalytics.Point],
        minDurationSeconds: Int = defaultMinDurationSeconds
    ) -> Fit? {
        let samples = points
            .filter { $0.durationSeconds >= minDurationSeconds && $0.watts > 0 }
            .sorted { $0.durationSeconds < $1.durationSeconds }

        guard samples.count >= 3 else { return nil }

        let x = samples.map { 1.0 / Double($0.durationSeconds) }
        let y = samples.map { Double($0.watts) }

        guard let regression = simpleLinearRegression(x: x, y: y) else { return nil }

        let cp = regression.intercept
        let wPrime = regression.slope
        guard cp.isFinite, wPrime.isFinite, cp > 0, wPrime > 0 else { return nil }

        return Fit(
            criticalPowerWatts: Int(cp.rounded()),
            wPrimeJoules: Int(wPrime.rounded()),
            rSquared: max(0, min(1, regression.rSquared)),
            sampleCount: samples.count
        )
    }

    /// Predicts sustainable power for a given duration using the fitted model.
    nonisolated static func predictedPower(durationSeconds: Int, fit: Fit) -> Int? {
        guard durationSeconds > 0 else { return nil }
        let cp = Double(fit.criticalPowerWatts)
        let wPrime = Double(fit.wPrimeJoules)
        let power = cp + wPrime / Double(durationSeconds)
        guard power.isFinite, power > 0 else { return nil }
        return Int(power.rounded())
    }

    private nonisolated struct LinearRegressionResult {
        let intercept: Double
        let slope: Double
        let rSquared: Double
    }

    private nonisolated static func simpleLinearRegression(
        x: [Double],
        y: [Double]
    ) -> LinearRegressionResult? {
        guard x.count == y.count, x.count >= 2 else { return nil }

        let n = Double(x.count)
        let xMean = x.reduce(0, +) / n
        let yMean = y.reduce(0, +) / n

        var ssXX = 0.0
        var ssXY = 0.0
        var ssYY = 0.0

        for i in 0..<x.count {
            let dx = x[i] - xMean
            let dy = y[i] - yMean
            ssXX += dx * dx
            ssXY += dx * dy
            ssYY += dy * dy
        }

        guard ssXX > 0 else { return nil }

        let slope = ssXY / ssXX
        let intercept = yMean - slope * xMean
        let rSquared = ssYY > 0 ? (ssXY * ssXY) / (ssXX * ssYY) : 0

        return LinearRegressionResult(intercept: intercept, slope: slope, rSquared: rSquared)
    }
}
