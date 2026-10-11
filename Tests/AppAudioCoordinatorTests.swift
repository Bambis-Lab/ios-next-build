import XCTest
@testable import IOSNext

@MainActor
final class AppAudioCoordinatorTests: XCTestCase {
    func testJarvisBusyStateChangesOnlyWhenFirstAndLastLeaseChanges() {
        var transitions: [Bool] = []
        let audio = AppAudioCoordinator { transitions.append($0) }

        let playback = audio.begin(.chatVoicePlayback)
        let recording = audio.begin(.voiceRecording)
        XCTAssertTrue(audio.isBusy)
        audio.end(playback)
        XCTAssertTrue(audio.isBusy)
        audio.end(recording)
        XCTAssertFalse(audio.isBusy)
        audio.end(recording)

        XCTAssertEqual(transitions, [true, false])
    }

    func testEndAllReleasesOnlyRequestedActivityKind() {
        var transitions: [Bool] = []
        let audio = AppAudioCoordinator { transitions.append($0) }
        _ = audio.begin(.chatVoicePlayback)
        _ = audio.begin(.chatVoicePlayback)
        let recording = audio.begin(.voiceRecording)

        audio.endAll(.chatVoicePlayback)
        XCTAssertTrue(audio.isBusy)
        audio.end(recording)
        XCTAssertFalse(audio.isBusy)
        XCTAssertEqual(transitions, [true, false])
    }
}
