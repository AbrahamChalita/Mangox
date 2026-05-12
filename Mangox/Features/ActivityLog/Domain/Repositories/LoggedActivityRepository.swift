// Features/ActivityLog/Domain/Repositories/LoggedActivityRepository.swift
import Foundation

@MainActor
protocol LoggedActivityRepository: AnyObject {
    func create(_ draft: LoggedActivityDraft) throws -> LoggedActivity
    func update(_ draft: LoggedActivityDraft) throws -> LoggedActivity
    func delete(id: UUID) throws

    func fetchAll(limit: Int?, source: LoggedActivitySource?) throws -> [LoggedActivity]
    func fetch(id: UUID) throws -> LoggedActivity?

    /// Returns true if an imported row with the given source+externalID already exists.
    func existsExternal(source: LoggedActivitySource, externalID: String) throws -> Bool
    /// Returns the most recent `startDate` among imported rows for a given source.
    func mostRecentExternalDate(source: LoggedActivitySource) throws -> Date?
    /// Inserts new imported rows; skips duplicates. Returns count of newly inserted rows.
    func upsertImported(_ batch: [LoggedActivityDraft]) throws -> Int
}
