import SwiftUI

enum MangoxMotion {
    static let press = Animation.easeInOut(duration: 0.12)
    static let micro = Animation.easeInOut(duration: 0.2)
    static let standard = Animation.easeInOut(duration: 0.25)
    static let smooth = Animation.spring(duration: 0.3)
    static let expansive = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let banner = Animation.smooth(duration: 0.28)
}
