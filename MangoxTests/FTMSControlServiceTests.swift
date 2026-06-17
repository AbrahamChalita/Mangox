import Testing
import Foundation
@testable import Mangox

@MainActor
struct FTMSControlServiceTests {

    @Test func mismatchedOpCodeDoesNotResumePendingContinuation() async {
        let service = FTMSControlService()
        var resumed = false

        let task = Task { @MainActor () -> FTMSResultCode in
            try await withCheckedThrowingContinuation { continuation in
                service.setPendingForTesting(opCode: .setTargetPower, continuation: continuation)
            }
        }

        // Stale response for a different op code (requestControl).
        service.parseControlPointResponseForTesting(Data([0x80, FTMSOpCode.requestControl.rawValue, FTMSResultCode.success.rawValue]))

        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(task.isCancelled == false)

        // Matching response for setTargetPower.
        service.parseControlPointResponseForTesting(Data([0x80, FTMSOpCode.setTargetPower.rawValue, FTMSResultCode.success.rawValue]))

        let result = try await task.value
        resumed = true
        #expect(resumed)
        #expect(result == .success)
    }

    @Test func matchingOpCodeResumesWithResultCode() async throws {
        let service = FTMSControlService()

        let task = Task { @MainActor () -> FTMSResultCode in
            try await withCheckedThrowingContinuation { continuation in
                service.setPendingForTesting(opCode: .reset, continuation: continuation)
            }
        }

        service.parseControlPointResponseForTesting(Data([0x80, FTMSOpCode.reset.rawValue, FTMSResultCode.operationFailed.rawValue]))

        let result = try await task.value
        #expect(result == .operationFailed)
    }
}
