// Features/Fitness/Domain/Entities/PowerToSpeed.swift
import Foundation

/// Physics-based power-to-speed model for indoor free rides.
///
/// Uses the standard cycling power equation:
///   P = (F_gravity + F_rolling + F_drag) × v
///
/// Where:
///   F_gravity = m × g × sin(grade)
///   F_rolling = m × g × Crr
///   F_drag    = 0.5 × ρ × CdA × v²
///
/// Solved for v via binary search since drag is quadratic.
enum PowerToSpeed {

    static let gravity: Double = 9.80665       // m/s²
    static let airDensity: Double = 1.225      // kg/m³ at sea level, 15°C

    /// Typical CdA (drag area) values for reference:
    /// - Hoods, relaxed:       ~0.32
    /// - Hoods, hands on top:  ~0.30
    /// - Drops:                ~0.28
    /// - Aero bars:            ~0.23
    static let defaultCdA: Double = 0.32

    /// Coefficient of rolling resistance:
    /// - Smooth road:          ~0.004
    /// - Rough road:           ~0.006
    /// - Trainer roller:       ~0.002–0.004 (depends on trainer model)
    static let defaultCrr: Double = 0.004

    // MARK: - Compute

    /// Returns estimated speed in km/h given power and physical parameters.
    ///
    /// - Parameters:
    ///   - powerWatts: Mechanical power at the crank (watts).
    ///   - totalMassKg: Combined rider + bike mass (kg).
    ///   - gradePercent: Road gradient (0 = flat, 5 = 5% climb).
    ///   - cda: Aerodynamic drag area (m²). Typical: 0.28–0.35.
    ///   - crr: Coefficient of rolling resistance. Typical: 0.002–0.006.
    ///   - drivetrainLoss: Fraction of power lost in drivetrain (0.03 = 3%).
    /// - Returns: Speed in km/h, or 0 if power ≤ 0.
    static func speedKmh(
        fromPower powerWatts: Double,
        totalMassKg: Double,
        gradePercent: Double,
        cda: Double = defaultCdA,
        crr: Double = defaultCrr,
        drivetrainLoss: Double = 0.03
    ) -> Double {
        guard powerWatts > 0, totalMassKg > 0 else { return 0 }

        let powerAtWheel = powerWatts * (1.0 - drivetrainLoss)
        let grade = gradePercent / 100.0

        // Forces that don't depend on speed
        let fGravity = totalMassKg * gravity * grade
        let fRolling = totalMassKg * gravity * crr

        // Drag force: 0.5 * rho * CdA * v²
        let dragCoeff = 0.5 * airDensity * cda

        // We need to find v such that:
        //   P = (fGravity + fRolling + dragCoeff * v²) * v
        //   P = fGravity * v + fRolling * v + dragCoeff * v³
        //
        // Binary search for v in [0, 25] m/s (0–90 km/h)
        var low: Double = 0
        var high: Double = 25.0  // ~90 km/h upper bound
        let tolerance: Double = 0.001  // ~0.0036 km/h precision

        for _ in 0..<50 {  // 50 iterations gives sub-millimeter precision
            let mid = (low + high) / 2
            let powerAtMid = (fGravity + fRolling + dragCoeff * mid * mid) * mid

            if powerAtMid < powerAtWheel {
                low = mid
            } else {
                high = mid
            }

            if high - low < tolerance { break }
        }

        let speedMPS = (low + high) / 2
        return max(0, speedMPS * 3.6)  // m/s → km/h
    }
}
