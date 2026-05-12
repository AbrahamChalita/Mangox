// Features/ActivityLog/Data/Repositories/LoggedActivityRepositoryImpl.swift
import Foundation
import SwiftData

@MainActor
final class LoggedActivityRepositoryImpl: LoggedActivityRepository {
    private let context: ModelContext
    private var onLocalChange: () -> Void

    init(modelContext: ModelContext, onLocalChange: @escaping () -> Void = {}) {
        self.context = modelContext
        self.onLocalChange = onLocalChange
    }

    func setOnLocalChange(_ block: @escaping () -> Void) {
        onLocalChange = block
    }

    func create(_ draft: LoggedActivityDraft) throws -> LoggedActivity {
        let record = LoggedActivityRecord(draft: draft)
        context.insert(record)
        try context.save()
        MangoxModelNotifications.postLoggedActivitiesAggregatesMayHaveChanged()
        onLocalChange()
        return record.toDomain()
    }

    func update(_ draft: LoggedActivityDraft) throws -> LoggedActivity {
        guard let record = try fetchRecord(id: draft.id) else {
            throw RepositoryError.notFound(draft.id)
        }
        record.apply(draft)
        try context.save()
        MangoxModelNotifications.postLoggedActivitiesAggregatesMayHaveChanged()
        onLocalChange()
        return record.toDomain()
    }

    func delete(id: UUID) throws {
        guard let record = try fetchRecord(id: id) else { return }
        context.delete(record)
        try context.save()
        MangoxModelNotifications.postLoggedActivitiesAggregatesMayHaveChanged()
        onLocalChange()
    }

    func fetchAll(limit: Int? = nil, source: LoggedActivitySource? = nil) throws -> [LoggedActivity] {
        var descriptor = FetchDescriptor<LoggedActivityRecord>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        if let source {
            descriptor.predicate = #Predicate { $0.sourceRaw == source.rawValue }
        }
        if let limit { descriptor.fetchLimit = limit }
        return try context.fetch(descriptor).map { $0.toDomain() }
    }

    func fetch(id: UUID) throws -> LoggedActivity? {
        try fetchRecord(id: id)?.toDomain()
    }

    func existsExternal(source: LoggedActivitySource, externalID: String) throws -> Bool {
        let sourceRaw = source.rawValue
        var descriptor = FetchDescriptor<LoggedActivityRecord>(
            predicate: #Predicate { $0.sourceRaw == sourceRaw && $0.externalID == externalID }
        )
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    func mostRecentExternalDate(source: LoggedActivitySource) throws -> Date? {
        let sourceRaw = source.rawValue
        var descriptor = FetchDescriptor<LoggedActivityRecord>(
            predicate: #Predicate { $0.sourceRaw == sourceRaw && $0.externalID != nil },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.startDate
    }

    func upsertImported(_ batch: [LoggedActivityDraft]) throws -> Int {
        var inserted = 0
        for draft in batch {
            guard let extID = draft.externalID else { continue }
            if let existing = try fetchExternalRecord(source: draft.source, externalID: extID) {
                existing.apply(draft)
                continue
            }
            let record = LoggedActivityRecord(draft: draft)
            context.insert(record)
            inserted += 1
        }
        if !batch.isEmpty {
            try context.save()
            MangoxModelNotifications.postLoggedActivitiesAggregatesMayHaveChanged()
            onLocalChange()
        }
        return inserted
    }

    // MARK: - Private

    private func fetchRecord(id: UUID) throws -> LoggedActivityRecord? {
        var descriptor = FetchDescriptor<LoggedActivityRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchExternalRecord(source: LoggedActivitySource, externalID: String) throws -> LoggedActivityRecord? {
        let sourceRaw = source.rawValue
        var descriptor = FetchDescriptor<LoggedActivityRecord>(
            predicate: #Predicate { $0.sourceRaw == sourceRaw && $0.externalID == externalID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    enum RepositoryError: LocalizedError {
        case notFound(UUID)
        var errorDescription: String? {
            switch self { case .notFound(let id): "LoggedActivity \(id) not found." }
        }
    }
}
