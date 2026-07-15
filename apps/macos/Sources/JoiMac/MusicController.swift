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

    enum NowPlayingCommand: Int32, Equatable {
        case togglePlayPause = 2
        case next = 4
        case previous = 5
        case advanceShuffleMode = 6
        case likeTrack = 21
        case addNowPlayingItemToLibrary = 127
    }

    enum CommandSupport: Equatable {
        case unavailable
        case unsupported
        case supported
    }

    enum PlaybackProbeState: Int32, Equatable, Sendable {
        case unavailable = -1
        case unknown = 0
        case playing = 1
        case paused = 2
        case stopped = 3
        case interrupted = 4
    }

    enum PlaybackObservation: Equatable, Sendable {
        case playing(ownerBundleIdentifier: String?)
        case notPlaying(ownerBundleIdentifier: String?)
        case unavailable(ownerBundleIdentifier: String?)
    }

    struct MediaProcessAudioSample: Equatable {
        let bundleIdentifier: String
        let isRunningOutput: Bool
        let isRunningInput: Bool
        let isInputStateKnown: Bool
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
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var permissionRequired = false
    @Published private(set) var automationPermissionRequired = false
    @Published private(set) var isPlaying = false

    static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!
    static let automationSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    )!

    private var pendingAction: Action?
    private var pendingOwnerBundleIdentifier: String?
    private var lastValidatedOwnerBundleIdentifier: String?
    private let playbackProbe: @Sendable () -> PlaybackObservation
    private var playbackMonitorTask: Task<Void, Never>?
    private var consecutiveUnavailableSamples = 0

    init(monitorPlayback: Bool = true) {
        playbackProbe = { MusicController.detectPlaybackObservation() }
        refreshAccessibilityPermission()
        if monitorPlayback {
            startPlaybackMonitor()
        }
    }

    /// Retained for deterministic self-tests and lightweight callers. The
    /// production initializer above uses the confidence-aware Now Playing probe.
    init(
        playbackProbe: @escaping @Sendable () -> Bool,
        monitorPlayback: Bool = true
    ) {
        self.playbackProbe = {
            playbackProbe()
                ? .playing(ownerBundleIdentifier: nil)
                : .notPlaying(ownerBundleIdentifier: nil)
        }
        refreshAccessibilityPermission()
        if monitorPlayback {
            startPlaybackMonitor()
        }
    }

    deinit {
        playbackMonitorTask?.cancel()
    }

    /// A synchronous hook keeps the playback detector independently testable.
    /// Production polling runs the same probe off the main actor.
    func refreshPlaybackState() {
        setPlaybackState(playbackProbe())
    }

    nonisolated static func detectActivePlayback() -> Bool {
        if case .playing = detectPlaybackObservation() {
            return true
        }
        return false
    }

    /// MediaRemote can distinguish an explicit pause/stop from a momentary
    /// owner-query failure. Core Audio is used only when that state is unknown,
    /// keeping browser playback supported without treating arbitrary audio as
    /// music.
    nonisolated static func detectPlaybackObservation() -> PlaybackObservation {
        let ownerBundleIdentifier = currentNowPlayingBundleIdentifier()
        if let ownerBundleIdentifier,
           !isSupportedMediaBundleIdentifier(ownerBundleIdentifier) {
            return .notPlaying(ownerBundleIdentifier: ownerBundleIdentifier)
        }

        if let ownerBundleIdentifier {
            let state = PlaybackProbeState(
                rawValue: JoiCurrentNowPlayingPlaybackState()
            ) ?? .unavailable
            switch state {
            case .playing:
                return .playing(ownerBundleIdentifier: ownerBundleIdentifier)
            case .paused, .stopped, .interrupted:
                return .notPlaying(ownerBundleIdentifier: ownerBundleIdentifier)
            case .unknown, .unavailable:
                if hasActiveSupportedMediaAudio(
                    matchingNowPlayingOwner: ownerBundleIdentifier
                ) {
                    return .playing(ownerBundleIdentifier: ownerBundleIdentifier)
                }
                return .unavailable(ownerBundleIdentifier: ownerBundleIdentifier)
            }
        }

        if hasActiveSupportedMediaAudio() {
            return .playing(ownerBundleIdentifier: nil)
        }
        return .unavailable(ownerBundleIdentifier: nil)
    }

    /// Definitive player states win immediately. Only an unavailable sample gets
    /// one 250 ms grace interval for an ordinary track/owner handoff.
    nonisolated static func playbackTransition(
        current: Bool,
        consecutiveUnavailableSamples: Int,
        observation: PlaybackObservation
    ) -> (isPlaying: Bool, unavailableSamples: Int) {
        switch observation {
        case .playing:
            return (true, 0)
        case .notPlaying:
            return (false, 0)
        case .unavailable:
            guard current else { return (false, 0) }
            let samples = consecutiveUnavailableSamples + 1
            return samples >= 2 ? (false, 0) : (true, samples)
        }
    }

    @discardableResult
    func perform(_ action: Action) -> Bool {
        if let mediaKey = Self.systemMediaKey(for: action) {
            guard let session = currentMediaSession else {
                lastMessage = "Start playback first, then Joi will control that source."
                return false
            }
            if session.hasActiveOutput {
                lastValidatedOwnerBundleIdentifier = session.ownerBundleIdentifier
            }
            pendingAction = action
            pendingOwnerBundleIdentifier = session.ownerBundleIdentifier

            if let command = Self.nowPlayingCommand(for: action),
               Self.commandSupport(for: command) != .unsupported,
               JoiSendNowPlayingCommand(command.rawValue) {
                permissionRequired = false
                lastMessage = "Command sent to the current media session."
                if action == .playPause {
                    optimisticallyTogglePlayback()
                }
                return true
            }

            guard Self.canUseMediaKeyFallback(
                hasActiveOutput: session.hasActiveOutput,
                matchesLastValidatedOwner: session.ownerBundleIdentifier
                    == lastValidatedOwnerBundleIdentifier
            ) else {
                lastMessage = "Start playback once before using the media-key fallback."
                return false
            }
            return performFallback(mediaKey: mediaKey)
        }

        guard let session = currentMediaSession else {
            lastMessage = unavailableMessage(for: action)
            return false
        }

        if action == .lyrics {
            guard let target = currentNativePlayer() else {
                lastMessage = unavailableMessage(for: action)
                return false
            }
            return openLyrics(for: target)
        }

        if Self.isArcBundleIdentifier(session.ownerBundleIdentifier) {
            guard session.hasActiveOutput else {
                lastMessage = "Spotify Web is not the active Arc media source."
                return false
            }
            if performArcSpotify(action) {
                automationPermissionRequired = false
                lastMessage = message(for: action)
                return true
            }
        }

        if let target = currentNativePlayer(requirePlaying: false) {
            let source = script(for: action, player: target)
            if !source.isEmpty {
                var error: NSDictionary?
                NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    lastMessage = error[NSAppleScript.errorMessage] as? String
                        ?? "Music control failed."
                } else {
                    lastMessage = message(for: action)
                    return true
                }
            }
        }

        for command in Self.nowPlayingFeatureCommands(for: action)
        where Self.commandSupport(for: command) == .supported {
            if JoiSendNowPlayingCommand(command.rawValue) {
                lastMessage = "Command sent to a player that advertises support."
                return true
            }
        }

        lastMessage = unavailableMessage(for: action)
        return false
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

    static func nowPlayingCommand(for action: Action) -> NowPlayingCommand? {
        switch action {
        case .previous: .previous
        case .playPause: .togglePlayPause
        case .next: .next
        case .favorite, .shuffle, .lyrics: nil
        }
    }

    static func nowPlayingFeatureCommands(for action: Action) -> [NowPlayingCommand] {
        switch action {
        case .shuffle:
            [.advanceShuffleMode]
        case .favorite:
            [.addNowPlayingItemToLibrary, .likeTrack]
        case .previous, .playPause, .next, .lyrics:
            []
        }
    }

    static func commandSupport(for command: NowPlayingCommand) -> CommandSupport {
        switch JoiNowPlayingCommandSupport(command.rawValue) {
        case 1: .supported
        case 0: .unsupported
        default: .unavailable
        }
    }

    func refreshAccessibilityPermission() {
        let shouldRetry = permissionRequired && pendingAction != nil
        accessibilityGranted = CGPreflightPostEventAccess()
        if accessibilityGranted {
            permissionRequired = false
            if shouldRetry {
                tryFallbackForLastAction()
            }
        }
    }

    func requestAccessibilityPermission() {
        accessibilityGranted = CGRequestPostEventAccess()
        if accessibilityGranted {
            permissionRequired = false
            tryFallbackForLastAction()
        } else {
            permissionRequired = true
            lastMessage = "Enable Joi in Accessibility, relaunch it, then choose Try Again."
            openAccessibilitySettings()
        }
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(Self.accessibilitySettingsURL)
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(Self.automationSettingsURL)
    }

    func retryPendingAction() {
        refreshAccessibilityPermissionWithoutRetry()
        guard accessibilityGranted else {
            requestAccessibilityPermission()
            return
        }
        permissionRequired = false
        tryFallbackForLastAction()
    }

    func tryFallbackForLastAction() {
        guard let pendingAction else {
            lastMessage = "Choose a playback button to test the current media session."
            return
        }
        guard let mediaKey = Self.systemMediaKey(for: pendingAction),
              let session = currentMediaSession,
              let pendingOwnerBundleIdentifier,
              Self.bundleIdentifiersShareMediaFamily(
                  session.ownerBundleIdentifier,
                  pendingOwnerBundleIdentifier
              ) else {
            lastMessage = "The current media session changed. Choose a playback button again."
            return
        }
        _ = performFallback(mediaKey: mediaKey)
    }

    @discardableResult
    private func performFallback(mediaKey: SystemMediaKey) -> Bool {
        refreshAccessibilityPermissionWithoutRetry()
        guard accessibilityGranted else {
            permissionRequired = true
            lastMessage = "macOS needs Accessibility permission for the fallback media key."
            return false
        }
        guard post(mediaKey: mediaKey) else {
            lastMessage = "macOS could not send that media control."
            return false
        }
        pendingAction = nil
        pendingOwnerBundleIdentifier = nil
        permissionRequired = false
        lastMessage = "Fallback media key sent."
        if mediaKey == .playPause {
            optimisticallyTogglePlayback()
        }
        return true
    }

    private func refreshAccessibilityPermissionWithoutRetry() {
        accessibilityGranted = CGPreflightPostEventAccess()
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

    static func canUseMediaKeyFallback(
        hasActiveOutput: Bool,
        matchesLastValidatedOwner: Bool
    ) -> Bool {
        hasActiveOutput || matchesLastValidatedOwner
    }

    /// Only apps that are expected to own a system Now Playing session may unlock
    /// transport keys. This deliberately excludes calls, games, system sounds, and
    /// arbitrary background audio that could otherwise make a Play key wake Music.
    nonisolated static func isSupportedMediaBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        let identifier = bundleIdentifier.lowercased()
        return supportedMediaBundleIdentifierPrefixes.contains { prefix in
            identifier == prefix || identifier.hasPrefix(prefix + ".")
        }
    }

    nonisolated static func isEligibleMediaOutput(
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

    nonisolated static func hasEligibleMediaPlayback(
        samples: [MediaProcessAudioSample],
        nowPlayingOwnerBundleIdentifier: String? = nil
    ) -> Bool {
        struct FamilyActivity {
            var hasOutput = false
            var hasInput = false
            var hasUnknownInput = false
            var isBrowser = false
        }

        let requiredFamily: String?
        if let nowPlayingOwnerBundleIdentifier {
            guard let family = mediaFamilyPrefix(for: nowPlayingOwnerBundleIdentifier) else {
                return false
            }
            requiredFamily = family
        } else {
            requiredFamily = nil
        }

        var families: [String: FamilyActivity] = [:]
        for sample in samples {
            guard let family = mediaFamilyPrefix(for: sample.bundleIdentifier),
                  requiredFamily == nil || family == requiredFamily else {
                continue
            }
            var activity = families[family] ?? FamilyActivity()
            activity.hasOutput = activity.hasOutput || sample.isRunningOutput
            activity.hasInput = activity.hasInput || sample.isRunningInput
            let browser = isBrowserBundleIdentifier(sample.bundleIdentifier)
            activity.isBrowser = activity.isBrowser || browser
            activity.hasUnknownInput = activity.hasUnknownInput
                || (browser && !sample.isInputStateKnown)
            families[family] = activity
        }

        return families.values.contains { activity in
            activity.hasOutput
                && (!activity.isBrowser
                    || (!activity.hasInput && !activity.hasUnknownInput))
        }
    }

    /// Core Audio exposes the actual processes producing output on macOS 14+.
    /// Requiring both active output and a recognized media/browser bundle keeps
    /// transport controls attached to what is already playing.
    nonisolated static func hasActiveSupportedMediaAudio(
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

        var samples: [MediaProcessAudioSample] = []
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
            samples.append(MediaProcessAudioSample(
                bundleIdentifier: bundleIdentifier,
                isRunningOutput: isRunningOutput != 0,
                isRunningInput: isRunningInput != 0,
                isInputStateKnown: inputStatus == noErr
            ))
        }
        return hasEligibleMediaPlayback(
            samples: samples,
            nowPlayingOwnerBundleIdentifier: ownerBundleIdentifier
        )
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

    private struct MediaSession {
        let ownerBundleIdentifier: String
        let hasActiveOutput: Bool
    }

    private var currentMediaSession: MediaSession? {
        guard let ownerBundleIdentifier = Self.currentNowPlayingBundleIdentifier(),
              Self.isSupportedMediaBundleIdentifier(ownerBundleIdentifier) else {
            return nil
        }
        return MediaSession(
            ownerBundleIdentifier: ownerBundleIdentifier,
            hasActiveOutput: Self.canControlTransport(
                activeSupportedMediaAudio: Self.hasActiveSupportedMediaAudio(
                    matchingNowPlayingOwner: ownerBundleIdentifier
                )
            )
        )
    }

    nonisolated static func currentNowPlayingBundleIdentifier() -> String? {
        let processIdentifier = JoiCurrentNowPlayingProcessIdentifier()
        guard processIdentifier > 0 else { return nil }
        return NSRunningApplication(
            processIdentifier: processIdentifier
        )?.bundleIdentifier
    }

    nonisolated private static let supportedMediaBundleIdentifierPrefixes = [
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

    nonisolated private static let browserBundleIdentifierPrefixes = [
        "company.thebrowser.browser",
        "com.apple.safari",
        "com.brave.browser",
        "com.google.chrome",
        "com.microsoft.edgemac",
        "com.operasoftware.opera",
        "com.vivaldi.vivaldi",
        "org.mozilla.firefox",
    ]

    nonisolated private static func isBrowserBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        let identifier = bundleIdentifier.lowercased()
        return browserBundleIdentifierPrefixes.contains { prefix in
            identifier == prefix || identifier.hasPrefix(prefix + ".")
        }
    }

    private static func isArcBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        let identifier = bundleIdentifier.lowercased()
        return identifier == "company.thebrowser.browser"
            || identifier.hasPrefix("company.thebrowser.browser.")
    }

    nonisolated private static func bundleIdentifiersShareMediaFamily(
        _ first: String,
        _ second: String
    ) -> Bool {
        guard let firstFamily = mediaFamilyPrefix(for: first),
              let secondFamily = mediaFamilyPrefix(for: second) else {
            return false
        }
        return firstFamily == secondFamily
    }

    nonisolated private static func mediaFamilyPrefix(for bundleIdentifier: String) -> String? {
        let identifier = bundleIdentifier.lowercased()
        return supportedMediaBundleIdentifierPrefixes.first { prefix in
            identifier == prefix || identifier.hasPrefix(prefix + ".")
        }
    }

    nonisolated private static func bundleIdentifier(
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
    private func currentNativePlayer(requirePlaying: Bool = true) -> Player? {
        guard let ownerBundleIdentifier = Self.currentNowPlayingBundleIdentifier(),
              let player = Player.allCases.first(where: {
                  Self.bundleIdentifiersShareMediaFamily(
                      $0.bundleIdentifier,
                      ownerBundleIdentifier
                  )
              }),
              isRunning(player),
              (!requirePlaying || isPlaying(player)) else {
            return nil
        }
        return player
    }

    static func arcSpotifyJavaScript(for action: Action) -> String? {
        switch action {
        case .shuffle:
            return """
            (() => {
              const ownsPlayback = navigator.mediaSession?.playbackState === 'playing'
                || [...document.querySelectorAll('audio, video')]
                  .some((media) => !media.paused && !media.ended);
              if (!ownsPlayback) return 'not_playing';
              const button = document.querySelector('[data-testid="control-button-shuffle"]');
              if (!(button instanceof HTMLButtonElement) || button.disabled) return 'not_found';
              button.click();
              return 'clicked:shuffle';
            })()
            """
        case .favorite:
            return """
            (() => {
              const ownsPlayback = navigator.mediaSession?.playbackState === 'playing'
                || [...document.querySelectorAll('audio, video')]
                  .some((media) => !media.paused && !media.ended);
              if (!ownsPlayback) return 'not_playing';
              const root = document.querySelector('[data-testid="now-playing-widget"]')
                || document.querySelector('[data-testid="now-playing-bar"]');
              if (!root) return 'not_found';
              const byTestID = root.querySelector('[data-testid="add-button"]');
              const byLabel = [...root.querySelectorAll('button')].find((candidate) => {
                const label = candidate.getAttribute('aria-label') || '';
                return /(save|add|remove).*(library|liked)/i.test(label);
              });
              const button = byTestID || byLabel;
              if (!(button instanceof HTMLButtonElement) || button.disabled) return 'not_found';
              button.click();
              return 'clicked:favorite';
            })()
            """
        case .previous, .playPause, .next, .lyrics:
            return nil
        }
    }

    static func arcSpotifyAppleScript(for action: Action) -> String? {
        guard let javaScript = arcSpotifyJavaScript(for: action) else {
            return nil
        }
        let encoded = Data(javaScript.utf8).base64EncodedString()
        let playbackProbe = """
        (() => {
          const playing = navigator.mediaSession?.playbackState === 'playing'
            || [...document.querySelectorAll('audio, video')]
              .some((media) => !media.paused && !media.ended && !media.muted);
          return playing ? 'playing' : 'idle';
        })()
        """
        let encodedProbe = Data(playbackProbe.utf8).base64EncodedString()
        return """
        set activeTabCount to 0
        set spotifyPlayingCount to 0
        tell application id "company.thebrowser.Browser"
            repeat with browserWindow in windows
                repeat with browserTab in tabs of browserWindow
                    set tabURL to URL of browserTab
                    try
                        set tabState to execute browserTab javascript "eval(atob('\(encodedProbe)'))"
                        if tabState is "playing" then
                            set activeTabCount to activeTabCount + 1
                            if tabURL starts with "https://open.spotify.com/" then
                                set spotifyPlayingCount to spotifyPlayingCount + 1
                            end if
                        end if
                    on error errorMessage number errorNumber
                        if errorNumber is -1743 then
                            return "error:" & errorNumber & ":" & errorMessage
                        end if
                        if tabURL starts with "https://open.spotify.com/" then
                            return "error:" & errorNumber & ":" & errorMessage
                        end if
                    end try
                end repeat
            end repeat
            if activeTabCount is not 1 or spotifyPlayingCount is not 1 then
                return "ambiguous_owner"
            end if
            repeat with browserWindow in windows
                repeat with browserTab in tabs of browserWindow
                    set tabURL to URL of browserTab
                    if tabURL starts with "https://open.spotify.com/" then
                        try
                            set tabState to execute browserTab javascript "eval(atob('\(encodedProbe)'))"
                            if tabState is "playing" then
                                set jsResult to execute browserTab javascript "eval(atob('\(encoded)'))"
                                if jsResult starts with "clicked:" then return jsResult
                            end if
                        on error errorMessage number errorNumber
                            return "error:" & errorNumber & ":" & errorMessage
                        end try
                    end if
                end repeat
            end repeat
        end tell
        return "not_found"
        """
    }

    private func performArcSpotify(_ action: Action) -> Bool {
        guard let source = Self.arcSpotifyAppleScript(for: action) else {
            return false
        }
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int
            automationPermissionRequired = number == -1_743
            lastMessage = error[NSAppleScript.errorMessage] as? String
                ?? "Arc did not allow this control."
            return false
        }
        if let result, result.hasPrefix("error:") {
            automationPermissionRequired = result.hasPrefix("error:-1743:")
            lastMessage = "Arc did not allow this control."
            return false
        }
        if result == "ambiguous_owner" {
            lastMessage = "Spotify Web is not the only active Arc media tab."
            return false
        }
        return result?.hasPrefix("clicked:") == true
    }

    private func isRunning(_ player: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier).isEmpty
    }

    private func startPlaybackMonitor() {
        playbackMonitorTask?.cancel()
        let probe = playbackProbe
        playbackMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                let detected = await Task.detached(priority: .utility) {
                    probe()
                }.value
                guard !Task.isCancelled, self != nil else { return }
                self?.setPlaybackState(detected)
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
            }
        }
    }

    private func setPlaybackState(_ observation: PlaybackObservation) {
        let transition = Self.playbackTransition(
            current: isPlaying,
            consecutiveUnavailableSamples: consecutiveUnavailableSamples,
            observation: observation
        )
        consecutiveUnavailableSamples = transition.unavailableSamples
        if isPlaying != transition.isPlaying {
            isPlaying = transition.isPlaying
        }
    }

    private func optimisticallyTogglePlayback() {
        consecutiveUnavailableSamples = 0
        isPlaying.toggle()
    }

    private func isPlaying(_ player: Player) -> Bool {
        guard isRunning(player) else { return false }
        let script = "tell application \"\(player.applicationName)\" to return (player state as text)"
        var error: NSDictionary?
        let state = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue
        return error == nil && state?.lowercased() == "playing"
    }

    private func openLyrics(for player: Player) -> Bool {
        guard isRunning(player), isPlaying(player) else {
            lastMessage = unavailableMessage(for: .lyrics)
            return false
        }

        let script = "tell application \"\(player.applicationName)\" to return (artist of current track) & \" — \" & (name of current track)"
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue
        guard error == nil, let result, let url = GoogleSearch.url(for: "\(result) lyrics") else {
            lastMessage = "Lyrics are unavailable for the current player."
            return false
        }
        guard NSWorkspace.shared.open(url) else {
            lastMessage = "Lyrics could not be opened in your browser."
            return false
        }
        lastMessage = "Lyrics opened in your browser."
        return true
    }

    private func unavailableMessage(for action: Action) -> String {
        switch action {
        case .shuffle:
            "The current player does not expose Shuffle to Joi."
        case .favorite:
            "The current player does not expose Favorite to Joi."
        case .lyrics:
            "Open lyrics from the app or browser that is currently playing."
        case .previous, .playPause, .next:
            "No active media session was found."
        }
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
