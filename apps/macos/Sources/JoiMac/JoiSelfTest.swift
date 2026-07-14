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

        let timer = PomodoroTimer(seconds: 2)
        timer.start()
        timer.tick(notifyOnCompletion: false)
        timer.tick(notifyOnCompletion: false)
        check(timer.state == .completed && timer.formattedRemaining == "00:00", "Pomodoro completion", failures: &failures)
        timer.reset()
        check(timer.state == .idle && timer.formattedRemaining == "00:02", "Pomodoro reset", failures: &failures)

        let event = RealtimeVoiceService.sessionUpdate(voice: "shimmer", instructions: AppModel.defaultPersona)
        let session = event["session"] as? [String: Any]
        let audio = session?["audio"] as? [String: Any]
        let output = audio?["output"] as? [String: Any]
        check(session?["model"] as? String == "gpt-realtime-2.1", "Realtime model pin", failures: &failures)
        check(output?["voice"] as? String == "shimmer", "default Joi voice", failures: &failures)
        check((session?["instructions"] as? String)?.contains("Always be transparent that you are an AI") == true, "AI disclosure prompt", failures: &failures)

        let music = MusicController()
        check(music.script(for: .next, player: .music) == "tell application \"Music\" to next track", "Apple Music command", failures: &failures)
        check(music.script(for: .shuffle, player: .spotify) == "tell application \"Spotify\" to set shuffling to not shuffling", "Spotify command", failures: &failures)

        if failures.isEmpty {
            print("Joi macOS self-test: 13 checks passed")
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
