import Testing
@testable import Mangox

/// Verifies that WorkoutMetricsAggregator's O(1) ring-buffer implementation
/// produces the same Normalized Power, Intensity Factor, and TSS as a naive
/// reference calculation, and handles all edge cases correctly.
struct WorkoutMetricsAggregatorTests {

    // MARK: - Reference implementation (straightforward O(n²) for comparison)

    /// Naive rolling-30s NP: for each window of 30, take avg, raise to 4th power.
    private func referenceNP(samples: [Int]) -> Double {
        guard samples.count >= 30 else {
            return Double(samples.reduce(0, +)) / Double(samples.count)
        }
        var sum4: Double = 0
        var count = 0
        for i in 29..<samples.count {
            let window = samples[(i - 29)...i]
            let avg = Double(window.reduce(0, +)) / 30.0
            sum4 += avg * avg * avg * avg
            count += 1
        }
        return pow(sum4 / Double(count), 0.25)
    }

    // MARK: - Guard conditions

    @Test func returnsZeroForEmptySamples() {
        let result = WorkoutMetricsAggregator.normalizedPowerIntensityAndTSS(
            powerSamples: [], durationSeconds: 60, ftp: 250
        )
        #expect(result.np == 0)
        #expect(result.intensityFactor == 0)
        #expect(result.tss == 0)
    }

    @Test func returnsZeroForZeroFTP() {
        let result = WorkoutMetricsAggregator.normalizedPowerIntensityAndTSS(
            powerSamples: Array(repeating: 200, count: 60), durationSeconds: 60, ftp: 0
        )
        #expect(result.np == 0)
        #expect(result.intensityFactor == 0)
        #expect(result.tss == 0)
    }

    @Test func returnsZeroForZeroDuration() {
        let result = WorkoutMetricsAggregator.normalizedPowerIntensityAndTSS(
            powerSamples: Array(repeating: 200, count: 60), durationSeconds: 0, ftp: 250
        )
        #expect(result.np == 0)
        #expect(result.intensityFactor == 0)
        #expect(result.tss == 0)
    }

    // MARK: - Short workouts (< 30 samples, falls back to average)

    @Test func shortWorkoutFallsBackToAverage() {
        let samples = [100, 200, 300, 200, 100] // 5 samples
        let ftp = 250.0
        let result = WorkoutMetricsAggregator.normalizedPowerIntensityAndTSS(
            powerSamples: samples, durationSeconds: 5, ftp: ftp
        )
        let expectedAvg = 180.0
        let expectedIF = expectedAvg / ftp
        let expectedTSS = (5.0 * expectedAvg * expectedIF) / (ftp * 3600) * 100

        #expect(abs(result.np - expectedAvg) < 0.001)
        #expect(abs(result.intensityFactor - expectedIF) < 0.001)
        #expect(abs(result.tss - expectedTSS) < 0.001)
    }

    @Test func singleSampleFallsBackToThatValue() {
        let ftp = 200.0
        let result = WorkoutMetricsAggregator.normalizedPowerIntensityAndTSS(
            powerSamples: [180], durationSeconds: 1, ftp: ftp
        )
        #expect(abs(result.np - 180.0) < 0.001)
        #expect(abs(result.intensityFactor - 0.9) < 0.001)
    }

    // MARK: - Constant power (NP should equal average)

    @Test func constantPower200WattsFTP250() {
        let samples = Array(repeating: 200, count: 60)
        let ftp = 250.0
        let result = WorkoutMetricsAggregator.normalizedPowerIntensityAndTSS(
            powerSamples: samples, durationSeconds: 60, ftp: ftp
        )
        // Constant power → NP equals average
        #expect(abs(result.np - 200.0) < 0.01)
        #expect(abs(result.intensityFactor - 0.8) < 0.001)
    }

    @Test func constantPowerAtFTPGivesIF1AndTSS100ForOneHour() {
        let ftp = 280.0
        let samples = Array(repeating: 280, count: 3600)
        let result = WorkoutMetricsAggregator.normalizedPowerIntensityAndTSS(
            powerSamples: samples, durationSeconds: 3600, ftp: ftp
        )
        #expect(abs(result.np - ftp) < 0.1)
        #expect(abs(result.intensityFactor - 1.0) < 0.001)
        #expect(abs(result.tss - 100.0) < 0.1)
    }

    // MARK: - O(1) ring buffer matches reference

    @Test func ringBufferMatchesReferenceForVariablePower60s() {
        let ftp = 250.0
        // Realistic variable-power distribution: intervals with recoveries
        var samples: [Int] = []
        for i in 0..<60 {
            let power = i % 10 < 5 ? 320 : 150
            samples.append(power)
        }

        let result = WorkoutMetricsAggregator.normalizedPowerIntensityAndTSS(
            powerSamples: samples, durationSeconds: 60, ftp: ftp
        )
        let expectedNP = referenceNP(samples: samples)
        #expect(abs(result.np - expectedNP) < 0.001)
    }

    @Test func ringBufferMatchesReferenceForLongRide3600s() {
        let ftp = 260.0
        var samples: [Int] = []
        // Simulate 1-hour ride with sweet spot intervals and Z1 recoveries
        for i in 0..<3600 {
            let phase = (i / 300) % 3
            switch phase {
            case 0: samples.append(234) // Z3 88% FTP
            case 1: samples.append(195) // Z2 75% FTP
            default: samples.append(150) // Z1 58% FTP
            }
        }

        let result = WorkoutMetricsAggregator.normalizedPowerIntensityAndTSS(
            powerSamples: samples, durationSeconds: 3600, ftp: ftp
        )
        let expectedNP = referenceNP(samples: samples)
        #expect(abs(result.np - expectedNP) < 0.01,
                "Ring buffer NP \(result.np) differs from reference \(expectedNP)")
    }

    @Test func ringBufferMatchesReferenceForExactly30Samples() {
        let ftp = 200.0
        let samples = Array(0..<30).map { $0 * 5 + 100 } // 100..245W ascending
        let result = WorkoutMetricsAggregator.normalizedPowerIntensityAndTSS(
            powerSamples: samples, durationSeconds: 30, ftp: ftp
        )
        let expectedNP = referenceNP(samples: samples)
        #expect(abs(result.np - expectedNP) < 0.001)
    }

    // MARK: - TSS formula

    @Test func tssFormula() {
        let ftp = 250.0
        let np = 200.0
        let duration = 3600
        let expectedIF = np / ftp
        let expectedTSS = (Double(duration) * np * expectedIF) / (ftp * 3600) * 100

        // Use constant power so NP = average = 200
        let samples = Array(repeating: 200, count: duration)
        let result = WorkoutMetricsAggregator.normalizedPowerIntensityAndTSS(
            powerSamples: samples, durationSeconds: duration, ftp: ftp
        )
        #expect(abs(result.tss - expectedTSS) < 0.5)
    }

    // MARK: - Zero power samples

    @Test func allZeroPowerProducesZeroNP() {
        let ftp = 250.0
        let samples = Array(repeating: 0, count: 60)
        let result = WorkoutMetricsAggregator.normalizedPowerIntensityAndTSS(
            powerSamples: samples, durationSeconds: 60, ftp: ftp
        )
        #expect(result.np == 0)
        #expect(result.tss == 0)
    }
}
