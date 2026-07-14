import AppKit
import Combine
import Foundation

@MainActor
final class MusicController: ObservableObject {
    enum Action: String, CaseIterable, Identifiable {
        case previous
        case playPause
        case next
        case favorite
        case shuffle
        case lyrics

        var id: String { rawValue }
    }

    @Published private(set) var lastMessage: String?

    func perform(_ action: Action) {
        if action == .lyrics {
            openLyrics()
            return
        }

        let target = activePlayer()
        if action == .favorite, target == .spotify {
            lastMessage = "Spotify's Mac app cannot favorite via Automation; use its + button."
            return
        }
        let script = script(for: action, player: target)
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            lastMessage = error[NSAppleScript.errorMessage] as? String ?? "Music control failed."
        } else {
            lastMessage = message(for: action)
        }
    }

    func script(for action: Action, player: Player) -> String {
        switch (player, action) {
        case (.music, .previous):
            return "tell application \"Music\" to previous track"
        case (.music, .playPause):
            return "tell application \"Music\" to playpause"
        case (.music, .next):
            return "tell application \"Music\" to next track"
        case (.music, .favorite):
            return "tell application \"Music\" to set favorited of current track to true"
        case (.music, .shuffle):
            return "tell application \"Music\" to set shuffle enabled to not shuffle enabled"
        case (.spotify, .previous):
            return "tell application \"Spotify\" to previous track"
        case (.spotify, .playPause):
            return "tell application \"Spotify\" to playpause"
        case (.spotify, .next):
            return "tell application \"Spotify\" to next track"
        case (.spotify, .favorite):
            return ""
        case (.spotify, .shuffle):
            return "tell application \"Spotify\" to set shuffling to not shuffling"
        case (_, .lyrics):
            return ""
        }
    }

    enum Player {
        case music
        case spotify
    }

    private func activePlayer() -> Player {
        let spotifyRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
        let musicRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
        if spotifyRunning, isPlaying(.spotify) {
            return .spotify
        }
        if musicRunning, isPlaying(.music) {
            return .music
        }
        if spotifyRunning {
            return .spotify
        }
        return .music
    }

    private func isPlaying(_ player: Player) -> Bool {
        let application = player == .spotify ? "Spotify" : "Music"
        let script = "tell application \"\(application)\" to return (player state as text)"
        var error: NSDictionary?
        let state = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue
        return error == nil && state?.lowercased() == "playing"
    }

    private func openLyrics() {
        let player = activePlayer()
        let application = player == .spotify ? "Spotify" : "Music"
        let script = "tell application \"\(application)\" to return (artist of current track) & \" — \" & (name of current track)"
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue
        guard error == nil, let result, let url = GoogleSearch.url(for: "\(result) lyrics") else {
            lastMessage = "Start a song first, then ask for lyrics."
            return
        }
        NSWorkspace.shared.open(url)
        lastMessage = "Lyrics opened in your browser."
    }

    private func message(for action: Action) -> String {
        switch action {
        case .previous: "Previous track"
        case .playPause: "Playback toggled"
        case .next: "Next track"
        case .favorite: "Added to favorites"
        case .shuffle: "Shuffle toggled"
        case .lyrics: "Lyrics opened"
        }
    }
}
