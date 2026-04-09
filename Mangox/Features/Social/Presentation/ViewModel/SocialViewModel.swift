// Features/Social/Presentation/ViewModel/SocialViewModel.swift
import Foundation

@MainActor
@Observable
final class SocialViewModel {
    // MARK: - View state
    var isSharing: Bool = false
    var shareError: String? = nil
    var storyOptions: InstagramStoryCardOptions = InstagramStoryStudioPreferences.load()

    func saveStoryOptions(_ options: InstagramStoryCardOptions) {
        storyOptions = options
        InstagramStoryStudioPreferences.save(options)
    }
}
