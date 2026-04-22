import SwiftUI

enum MangoxSpacing: CGFloat {
    case xs = 4
    case sm = 6
    case md = 10
    case lg = 14
    case xl = 20
    case xxl = 32

    static let page: CGFloat = MangoxSpacing.xl.rawValue
}
