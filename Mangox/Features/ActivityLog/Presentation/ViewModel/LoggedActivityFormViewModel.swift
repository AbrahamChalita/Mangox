// Features/ActivityLog/Presentation/ViewModel/LoggedActivityFormViewModel.swift
import Foundation
import Observation

@Observable
@MainActor
final class LoggedActivityFormViewModel {
    var draft: LoggedActivityDraft
    private(set) var isSaving = false
    private(set) var errorMessage: String? = nil
    private(set) var didSave = false

    var isEditing: Bool { editingID != nil }

    private let repository: LoggedActivityRepository
    private let editingID: UUID?

    var durationHours: Int {
        get { draft.durationSeconds / 3600 }
        set { draft.durationSeconds = newValue * 3600 + durationMinutes * 60 }
    }

    var durationMinutes: Int {
        get { (draft.durationSeconds % 3600) / 60 }
        set { draft.durationSeconds = durationHours * 3600 + newValue * 60 }
    }

    var isValid: Bool {
        draft.durationSeconds >= 60 &&
        (draft.type != .other || !(draft.customLabel ?? "").isEmpty)
    }

    init(repository: LoggedActivityRepository, editingID: UUID? = nil) {
        self.repository = repository
        self.editingID = editingID
        self.draft = .manual()

        if let id = editingID, let existing = try? repository.fetch(id: id) {
            draft = LoggedActivityDraft(
                id: existing.id,
                source: existing.source,
                externalID: existing.externalID,
                type: existing.type,
                customLabel: existing.customLabel,
                startDate: existing.startDate,
                durationSeconds: existing.durationSeconds,
                intensity: existing.intensity,
                rpe: existing.rpe,
                notes: existing.notes,
                metrics: existing.metrics
            )
        }
    }

    func dismissError() { errorMessage = nil }

    func save() async {
        guard isValid, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            if isEditing {
                _ = try repository.update(draft)
            } else {
                _ = try repository.create(draft)
            }
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
