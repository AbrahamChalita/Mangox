import SwiftUI

enum MangoxSpacing: CGFloat {
    case xs = 4
    case sm = 8
    case md = 12
    case lg = 16
    case xl = 20
    case xxl = 24

    static let page: CGFloat = MangoxSpacing.xl.rawValue
}
