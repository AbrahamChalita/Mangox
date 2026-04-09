// Features/Onboarding/Presentation/ViewModel/OnboardingViewModel.swift
import Foundation

@MainActor
@Observable
final class OnboardingViewModel {
    // MARK: - View state
    var currentStep: Int = 0
    var isComplete: Bool = false

    func advance() {
        currentStep += 1
    }

    func complete() {
        isComplete = true
    }
}
