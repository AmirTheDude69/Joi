import AppKit
import Combine
import CoreAudio
import Foundation
import MediaRemoteShim

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

    /// Consumer-page usages used by the system media keys. These are intentionally
    /// sent through macOS rather than to a named app so the current Now Playing
    /// session wins, including Spotify in Arc, Safari, or another browser.
    enum SystemMediaKey: Int, Equatable {
        case playPause = 16
        case next = 17
        case previous = 18
    }

    enum Player: CaseIterable, Equatable {
        case spotify
        case music

        var bundleIdentifier: String {
            switch self {
            case .spotify: "com.spotify.client"
            case .music: "com.apple.Music"
            }
        }

        var applicationName: String {
            switch self {
            case .spotify: "Spotify"
            case .music: "Music"
            }
        }
    }

    @Published private(set) var lastMessage: String?

    func perform(_ action: Action) {
        if let mediaKey = Self.systemMediaKey(for: action) {
            guard hasCurrentMediaSession else {
                lastMessage = "Start playback first, then Joi will control that source."
                return
            }
            guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
                lastMessage = "Allow Joi in System Settings → Privacy & Security → Accessibility."
                return
            }
            guard post(mediaKey: mediaKey) else {
                lastMessage = "macOS could not send that media control."
                return
            }
            lastMessage = message(for: action)
            return
        }

        guard let target = currentNativePlayer() else {
            lastMessage = unavailableMessage(for: action)
            return
        }

        if action == .lyrics {
            openLyrics(for: target)
            return
        }

        if action == .favorite, target == .spotify {
            lastMessage = "Use Spotify's + button to save the current song."
            return
        }

        let source = script(for: action, player: target)
        guard !source.isEmpty else {
            lastMessage = unavailableMessage(for: action)
            return
        }

        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            lastMessage = error[NSAppleScript.errorMessage] as? String ?? "Music control failed."
        } else {
            lastMessage = message(for: action)
        }
    }

    /// App-specific scripting is deliberately limited to capabilities that do not
    /// have a system media key. Transport controls never use this path because a
    /// `tell application` command can launch or target the wrong player.
    func script(for action: Action, player: Player) -> String {
        switch (player, action) {
        case (.music, .favorite):
            return "tell application \"Music\" to set favorited of current track to true"
        case (.music, .shuffle):
            return "tell application \"Music\" to set shuffle enabled to not shuffle enabled"
        case (.spotify, .shuffle):
            return "tell application \"Spotify\" to set shuffling to not shuffling"
        default:
            return ""
        }
    }

    static func systemMediaKey(for action: Action) -> SystemMediaKey? {
        switch action {
        case .previous: .previous
        case .playPause: .playPause
        case .next: .next
        case .favorite, .shuffle, .lyrics: nil
        }
    }

    static func eventData(for mediaKey: SystemMediaKey, isKeyDown: Bool) -> Int {
        let keyState = isKeyDown ? 0xA : 0xB
        return (mediaKey.rawValue << 16) | (keyState << 8)
    }

    static func eventModifierFlags(isKeyDown: Bool) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(isKeyDown ? 0xA00 : 0xB00))
    }

    static func canControlTransport(activeSupportedMediaAudio: Bool) -> Bool {
        activeSupportedMediaAudio
    }

    /// Only apps that are expected to own a system Now Playing session may unlock
    /// transport keys. This deliberately excludes calls, games, system sounds, and
    /// arbitrary background audio that could otherwise make a Play key wake Music.
    static func isSupportedMediaBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        let identifier = bundleIdentifier.lowercased()
        return supportedMediaBundleIdentifierPrefixes.contains { prefix in
            identifier == prefix || identifier.hasPrefix(prefix + ".")
        }
    }

    static func isEligibleMediaOutput(
        bundleIdentifier: String,
        isRunningOutput: Bool,
        isRunningInput: Bool,
        nowPlayingOwnerBundleIdentifier: String? = nil
    ) -> Bool {
        guard isRunningOutput, isSupportedMediaBundleIdentifier(bundleIdentifier) else {
            return false
        }
        if let nowPlayingOwnerBundleIdentifier,
           !bundleIdentifiersShareMediaFamily(
               bundleIdentifier,
               nowPlayingOwnerBundleIdentifier
           ) {
            return false
        }
        // A browser producing input and output is normally a call rather than a
        // controllable song/video. Refuse the media key so it cannot fall through
        // to launching Music.
        return !isBrowserBundleIdentifier(bundleIdentifier) || !isRunningInput
    }

    /// Core Audio exposes the actual processes producing output on macOS 14+.
    /// Requiring both active output and a recognized media/browser bundle keeps
    /// transport controls attached to what is already playing.
    static func hasActiveSupportedMediaAudio(
        matchingNowPlayingOwner ownerBundleIdentifier: String? = nil,
        excludingProcessIdentifier excludedPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> Bool {
        var processListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processListSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &processListAddress,
            0,
            nil,
            &processListSize
        ) == noErr, processListSize > 0 else { return false }

        let count = Int(processListSize) / MemoryLayout<AudioObjectID>.stride
        var processObjects = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
        let listStatus = processObjects.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &processListAddress,
                0,
                nil,
                &processListSize,
                bytes.baseAddress!
            )
        }
        guard listStatus == noErr else { return false }

        for processObject in processObjects where processObject != kAudioObjectUnknown {
            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var processIdentifier = pid_t(0)
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(
                processObject,
                &pidAddress,
                0,
                nil,
                &pidSize,
                &processIdentifier
            ) == noErr, processIdentifier != excludedPID else { continue }

            guard let bundleIdentifier = bundleIdentifier(
                for: processObject,
                processIdentifier: processIdentifier
            ) else { continue }

            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningOutput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var isRunningOutput: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(
                processObject,
                &runningAddress,
                0,
                nil,
                &runningSize,
                &isRunningOutput
            ) == noErr else { continue }

            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var isRunningInput: UInt32 = 0
            var inputSize = UInt32(MemoryLayout<UInt32>.size)
            let inputStatus = AudioObjectGetPropertyData(
                processObject,
                &inputAddress,
                0,
                nil,
                &inputSize,
                &isRunningInput
            )
            // Browser input state is part of the call-safety gate. If Core Audio
            // cannot provide it, do not guess that the browser is safe.
            if Self.isBrowserBundleIdentifier(bundleIdentifier), inputStatus != noErr {
                continue
            }

            if isEligibleMediaOutput(
                bundleIdentifier: bundleIdentifier,
                isRunningOutput: isRunningOutput != 0,
                isRunningInput: isRunningInput != 0,
                nowPlayingOwnerBundleIdentifier: ownerBundleIdentifier
            ) {
                return true
            }
        }
        return false
    }

    @discardableResult
    private func post(mediaKey: SystemMediaKey) -> Bool {
        let keyDown = mediaEvent(for: mediaKey, isKeyDown: true)
        let keyUp = mediaEvent(for: mediaKey, isKeyDown: false)
        guard let keyDown, let keyUp else { return false }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func mediaEvent(for mediaKey: SystemMediaKey, isKeyDown: Bool) -> CGEvent? {
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: Self.eventModifierFlags(isKeyDown: isKeyDown),
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Self.eventData(for: mediaKey, isKeyDown: isKeyDown),
            data2: -1
        )
        return event?.cgEvent
    }

    private var hasCurrentMediaSession: Bool {
        guard let ownerBundleIdentifier = Self.currentNowPlayingBundleIdentifier(),
              Self.isSupportedMediaBundleIdentifier(ownerBundleIdentifier) else {
            return false
        }
        return Self.canControlTransport(
            activeSupportedMediaAudio: Self.hasActiveSupportedMediaAudio(
                matchingNowPlayingOwner: ownerBundleIdentifier
            )
        )
    }

    static func currentNowPlayingBundleIdentifier() -> String? {
        let processIdentifier = JoiCurrentNowPlayingProcessIdentifier()
        guard processIdentifier > 0 else { return nil }
        return NSRunningApplication(
            processIdentifier: processIdentifier
        )?.bundleIdentifier
    }

    private static let supportedMediaBundleIdentifierPrefixes = [
        "company.thebrowser.browser", // Arc
        "com.apple.music",
        "com.apple.podcasts",
        "com.apple.quicktimeplayerx",
        "com.apple.safari",
        "com.apple.tv",
        "com.brave.browser",
        "com.colliderli.iina",
        "com.google.chrome",
        "com.microsoft.edgemac",
        "com.operasoftware.opera",
        "com.spotify.client",
        "com.tidal.desktop",
        "com.vivaldi.vivaldi",
        "org.mozilla.firefox",
        "org.videolan.vlc",
    ]

    private static let browserBundleIdentifierPrefixes = [
        "company.thebrowser.browser",
        "com.apple.safari",
        "com.brave.browser",
        "com.google.chrome",
        "com.microsoft.edgemac",
        "com.operasoftware.opera",
        "com.vivaldi.vivaldi",
        "org.mozilla.firefox",
    ]

    private static func isBrowserBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        let identifier = bundleIdentifier.lowercased()
        return browserBundleIdentifierPrefixes.contains { prefix in
            identifier == prefix || identifier.hasPrefix(prefix + ".")
        }
    }

    private static func bundleIdentifiersShareMediaFamily(
        _ first: String,
        _ second: String
    ) -> Bool {
        guard let firstFamily = mediaFamilyPrefix(for: first),
              let secondFamily = mediaFamilyPrefix(for: second) else {
            return false
        }
        return firstFamily == secondFamily
    }

    private static func mediaFamilyPrefix(for bundleIdentifier: String) -> String? {
        let identifier = bundleIdentifier.lowercased()
        return supportedMediaBundleIdentifierPrefixes.first { prefix in
            identifier == prefix || identifier.hasPrefix(prefix + ".")
        }
    }

    private static func bundleIdentifier(
        for processObject: AudioObjectID,
        processIdentifier: pid_t
    ) -> String? {
        if let identifier = NSRunningApplication(
            processIdentifier: processIdentifier
        )?.bundleIdentifier {
            return identifier
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                processObject,
                &address,
                0,
                nil,
                &size,
                pointer
            )
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// Returns a scriptable player only when its process is already running and it
    /// reports active playback. This prevents every fallback from opening Music or
    /// Spotify and avoids stealing controls from a browser's Now Playing session.
    private func currentNativePlayer() -> Player? {
        guard let ownerBundleIdentifier = Self.currentNowPlayingBundleIdentifier(),
              let player = Player.allCases.first(where: {
                  Self.bundleIdentifiersShareMediaFamily(
                      $0.bundleIdentifier,
                      ownerBundleIdentifier
                  )
              }),
              isRunning(player),
              isPlaying(player) else {
            return nil
        }
        return player
    }

    private func isRunning(_ player: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier).isEmpty
    }

    private func isPlaying(_ player: Player) -> Bool {
        guard isRunning(player) else { return false }
        let script = "tell application \"\(player.applicationName)\" to return (player state as text)"
        var error: NSDictionary?
        let state = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue
        return error == nil && state?.lowercased() == "playing"
    }

    private func openLyrics(for player: Player) {
        guard isRunning(player), isPlaying(player) else {
            lastMessage = unavailableMessage(for: .lyrics)
            return
        }

        let script = "tell application \"\(player.applicationName)\" to return (artist of current track) & \" — \" & (name of current track)"
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue
        guard error == nil, let result, let url = GoogleSearch.url(for: "\(result) lyrics") else {
            lastMessage = "Lyrics are unavailable for the current player."
            return
        }
        NSWorkspace.shared.open(url)
        lastMessage = "Lyrics opened in your browser."
    }

    private func unavailableMessage(for action: Action) -> String {
        switch action {
        case .shuffle:
            "Use Shuffle in the app or browser that is currently playing."
        case .favorite:
            "Use Favorite in the app or browser that is currently playing."
        case .lyrics:
            "Open lyrics from the app or browser that is currently playing."
        case .previous, .playPause, .next:
            "No active media session was found."
        }
    }

    private func message(for action: Action) -> String {
        switch action {
        case .previous: "Previous track"
        case .playPause: "Playback paused"
        case .next: "Next track"
        case .favorite: "Added to favorites"
        case .shuffle: "Shuffle toggled"
        case .lyrics: "Lyrics opened"
        }
    }
}
