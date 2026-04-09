// Features/Training/Data/DataSources/FTPRefreshTrigger.swift
import Foundation
import Observation

/// Bumped whenever `PowerZone.ftp` changes so SwiftUI views can depend on
/// `generation` and re-render (static `UserDefaults` values are not observable).
@Observable
final class FTPRefreshTrigger {
    static let shared = FTPRefreshTrigger()
    private(set) var generation: UInt64 = 0
    private init() {}
    func bump() { generation &+= 1 }
}
