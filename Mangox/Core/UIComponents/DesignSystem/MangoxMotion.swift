import SwiftUI

enum MangoxMotion {
    static let press = Animation.easeInOut(duration: 0.12)
    static let micro = Animation.easeInOut(duration: 0.2)
    static let standard = Animation.easeInOut(duration: 0.25)
    static let smooth = Animation.spring(duration: 0.3)
    static let expansive = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let banner = Animation.smooth(duration: 0.28)

    static let quick = Animation.easeOut(duration: 0.15)
    static let snappy = Animation.snappy(duration: 0.25, extraBounce: 0.05)

    static let entrance = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let entranceQuick = Animation.easeOut(duration: 0.2)

    static let exit = Animation.easeIn(duration: 0.18)
    static let fadeOut = Animation.easeOut(duration: 0.15)

    static let springy = Animation.spring(response: 0.5, dampingFraction: 0.65)
    static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.55)

    static let sheet = Animation.spring(response: 0.32, dampingFraction: 0.85)
    static let sheetQuick = Animation.spring(response: 0.25, dampingFraction: 0.8)

    static let highlight = Animation.easeInOut(duration: 0.12)
    static let pulse = Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)
}
