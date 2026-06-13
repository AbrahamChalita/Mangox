import Foundation
import FoundationModels

// MARK: - Dynamic Profile hooks (onPrompt / onResponse / onToolCall)

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
extension LanguageModelSession.DynamicProfile {
    /// Records prompt/response/tool-call events for Precision Coach telemetry and token debugging.
    func mangoxCoachInstrumentation(mode: CoachAgentMode) -> some LanguageModelSession.DynamicProfile {
        self
            .onPrompt { prompt in
                MangoxFoundationModelsSupport.recordDynamicProfilePrompt(mode: mode, prompt: prompt)
            }
            .onResponse { response in
                MangoxFoundationModelsSupport.recordDynamicProfileResponse(mode: mode, response: response)
            }
            .onToolCall { toolCall in
                MangoxFoundationModelsSupport.recordDynamicProfileToolCall(mode: mode, toolCall: toolCall)
            }
    }
}
