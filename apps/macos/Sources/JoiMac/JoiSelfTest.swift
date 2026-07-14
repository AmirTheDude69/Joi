import CoreGraphics
import Foundation

@MainActor
enum JoiSelfTest {
    static func run() -> Int32 {
        var failures: [String] = []

        let center = CGPoint(x: 250, y: 250)
        let voice = RadialLayout.point(for: .voice, center: center, radius: 100)
        let settings = RadialLayout.point(for: .settings, center: center, radius: 100)
        check(abs(voice.x - 250) < 0.001 && abs(voice.y - 150) < 0.001, "voice is at 12 o'clock", failures: &failures)
        check(abs(settings.x - 250) < 0.001 && abs(settings.y - 350) < 0.001, "settings is at 6 o'clock", failures: &failures)
        check(RadialLayout.point(for: .codex, center: center, radius: 100).x < center.x, "Codex is bottom-left", failures: &failures)
        check(RadialLayout.point(for: .pomodoro, center: center, radius: 100).x > center.x, "Pomodoro is bottom-right", failures: &failures)
        check(RadialLayout.point(for: .music, center: center, radius: 100).x < center.x, "music is top-left", failures: &failures)
        check(RadialLayout.point(for: .search, center: center, radius: 100).x > center.x, "search is top-right", failures: &failures)

        let search = GoogleSearch.url(for: "Joi tiny assistant & macOS")
        let searchValue = search.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first?.value
        check(search?.host == "www.google.com" && searchValue == "Joi tiny assistant & macOS", "Google query encoding", failures: &failures)
        check(GoogleSearch.url(for: "   ") == nil, "blank searches are ignored", failures: &failures)

        var completionSoundCount = 0
        var completionNotificationCount = 0
        let timer = PomodoroTimer(
            seconds: 2,
            completionSound: { completionSoundCount += 1 },
            completionNotification: { completionNotificationCount += 1 }
        )
        timer.start()
        timer.tick()
        timer.tick()
        check(timer.state == .completed && timer.formattedRemaining == "00:00", "Pomodoro completion", failures: &failures)
        check(completionSoundCount == 1, "Pomodoro completion emits one audible alert", failures: &failures)
        check(completionNotificationCount == 1, "Pomodoro completion requests one notification", failures: &failures)
        timer.reset()
        check(timer.state == .idle && timer.formattedRemaining == "00:02", "Pomodoro reset", failures: &failures)

        let event = RealtimeVoiceService.sessionUpdate(voice: "shimmer", instructions: AppModel.defaultPersona)
        let session = event["session"] as? [String: Any]
        let audio = session?["audio"] as? [String: Any]
        let input = audio?["input"] as? [String: Any]
        let output = audio?["output"] as? [String: Any]
        let turnDetection = input?["turn_detection"] as? [String: Any]
        let outputFormat = output?["format"] as? [String: Any]
        check(session?["model"] as? String == "gpt-realtime-2.1", "Realtime model pin", failures: &failures)
        check(output?["voice"] as? String == "shimmer", "default Joi voice", failures: &failures)
        check((session?["instructions"] as? String)?.contains("Always be transparent that you are an AI") == true, "AI disclosure prompt", failures: &failures)
        check(turnDetection?["type"] as? String == "semantic_vad" && turnDetection?["create_response"] as? Bool == true, "continuous semantic VAD", failures: &failures)
        check(
            outputFormat?["type"] as? String == "audio/pcm"
                && outputFormat?["rate"] as? Int == 24_000,
            "Realtime PCM output includes required 24 kHz rate",
            failures: &failures
        )
        check(SpriteAnimation.runningRight.row == 1 && SpriteAnimation.runningLeft.row == 2, "directional running rows", failures: &failures)
        check(SpriteAnimation.allCases.map(\.row) == Array(0 ... 8), "all standard animation rows mapped", failures: &failures)
        check(SpriteAnimation.allCases.map { $0.durations.count } == [7, 8, 8, 4, 5, 8, 6, 6, 6], "every populated standard frame is animated", failures: &failures)
        check(SpriteLookDirection.toward(pointer: CGPoint(x: 250, y: 150), from: center)?.index == 0, "gaze points up", failures: &failures)
        check(SpriteLookDirection.toward(pointer: CGPoint(x: 350, y: 250), from: center)?.index == 4, "gaze points right", failures: &failures)
        check(timer.remainingProgress == 1, "Pomodoro progress resets", failures: &failures)

        let music = MusicController()
        _ = MusicController.hasActiveSupportedMediaAudio()
        _ = MusicController.currentNowPlayingBundleIdentifier()
        check(
            MusicController.systemMediaKey(for: .previous) == .previous
                && MusicController.systemMediaKey(for: .playPause) == .playPause
                && MusicController.systemMediaKey(for: .next) == .next,
            "transport controls use system-wide media keys",
            failures: &failures
        )
        check(
            MusicController.systemMediaKey(for: .favorite) == nil
                && MusicController.systemMediaKey(for: .shuffle) == nil
                && MusicController.systemMediaKey(for: .lyrics) == nil,
            "unsupported media keys use guarded feature fallbacks",
            failures: &failures
        )
        check(
            MusicController.eventData(for: .playPause, isKeyDown: true) == (16 << 16) | (0xA << 8)
                && MusicController.eventData(for: .playPause, isKeyDown: false) == (16 << 16) | (0xB << 8)
                && MusicController.eventModifierFlags(isKeyDown: true).rawValue == 0xA00
                && MusicController.eventModifierFlags(isKeyDown: false).rawValue == 0xB00,
            "media key down and up events are well formed",
            failures: &failures
        )
        check(
            MusicController.canControlTransport(activeSupportedMediaAudio: true)
                && !MusicController.canControlTransport(activeSupportedMediaAudio: false),
            "transport guard requires active supported media",
            failures: &failures
        )
        check(
            MusicController.isSupportedMediaBundleIdentifier("company.thebrowser.Browser.helper")
                && MusicController.isSupportedMediaBundleIdentifier("com.spotify.client")
                && !MusicController.isSupportedMediaBundleIdentifier("us.zoom.xos")
                && !MusicController.isSupportedMediaBundleIdentifier("com.hnc.Discord"),
            "media owner allowlist includes Arc and Spotify but excludes calls",
            failures: &failures
        )
        check(
            MusicController.isEligibleMediaOutput(
                bundleIdentifier: "company.thebrowser.Browser",
                isRunningOutput: true,
                isRunningInput: false,
                nowPlayingOwnerBundleIdentifier: "company.thebrowser.Browser"
            )
                && !MusicController.isEligibleMediaOutput(
                    bundleIdentifier: "company.thebrowser.Browser",
                    isRunningOutput: true,
                    isRunningInput: true,
                    nowPlayingOwnerBundleIdentifier: "company.thebrowser.Browser"
                )
                && !MusicController.isEligibleMediaOutput(
                    bundleIdentifier: "us.zoom.xos",
                    isRunningOutput: true,
                    isRunningInput: false
                )
                && !MusicController.isEligibleMediaOutput(
                    bundleIdentifier: "company.thebrowser.Browser.helper",
                    isRunningOutput: true,
                    isRunningInput: false,
                    nowPlayingOwnerBundleIdentifier: "com.apple.Music"
                ),
            "transport output must match the real Now Playing owner",
            failures: &failures
        )
        check(music.script(for: .next, player: .music).isEmpty, "transport controls cannot launch a named player", failures: &failures)
        check(music.script(for: .shuffle, player: .spotify) == "tell application \"Spotify\" to set shuffling to not shuffling", "Spotify command", failures: &failures)
        check(music.script(for: .favorite, player: .spotify).isEmpty, "Spotify read-only favorite is not misrepresented", failures: &failures)

        let suiteName = "JoiSelfTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let panelTimer = PomodoroTimer(seconds: 1, completionSound: {}, completionNotification: {})
        let panelModel = AppModel(defaults: defaults, pomodoro: panelTimer)
        panelModel.togglePanel(.pomodoro)
        check(panelModel.activePanel == .pomodoro, "Focus panel opens", failures: &failures)
        panelModel.togglePanel(.pomodoro)
        check(panelModel.activePanel == .none, "Focus panel closes from the same control", failures: &failures)
        panelTimer.start()
        panelTimer.tick(notifyOnCompletion: false)
        panelModel.pomodoroMinutes = 15
        check(panelTimer.state == .idle && panelTimer.configuredMinutes == 15, "completed Focus preset reconfigures the next timer", failures: &failures)
        defaults.removePersistentDomain(forName: suiteName)

        if failures.isEmpty {
            print("Joi macOS self-test: 35 checks passed")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            print("Joi macOS self-test: \(failures.count) failure(s)")
        }
        return Int32(failures.count)
    }

    private static func check(_ condition: Bool, _ name: String, failures: inout [String]) {
        if !condition { failures.append(name) }
    }
}
