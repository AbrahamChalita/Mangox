import SwiftUI

/// Active coach delivery path while a turn is in flight (pending bubble chrome).
enum CoachStreamDelivery: Equatable, Sendable {
    case cloud
    case onDevice
    case pcc
    case webSearch
    case planIntake

    var appearance: CoachResponseAppearance {
        switch self {
        case .cloud: .cloud
        case .onDevice: .onDevice
        case .pcc: .pcc
        case .webSearch: .webSearch
        case .planIntake: .planIntake
        }
    }

    static func forPCCTurn(planIntake: Bool, webSearch: Bool) -> CoachStreamDelivery {
        if planIntake { return .planIntake }
        if webSearch { return .webSearch }
        return .pcc
    }
}
