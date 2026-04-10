// Features/Social/Presentation/View/InstagramStoryAccent+Color.swift
import SwiftUI

/// Presentation-layer mapping from the Domain `colorKey` to a SwiftUI `Color`.
/// Keeps the Domain entity free of SwiftUI dependencies.
extension InstagramStoryCardOptions.Accent {
    /// The SwiftUI `Color` for this accent option.
    var color: Color {
        switch colorKey {
        case "orange": return AppColor.orange
        case "mango":  return AppColor.mango
        default:       return AppColor.orange
        }
    }
}
