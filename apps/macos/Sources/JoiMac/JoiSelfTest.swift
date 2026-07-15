import AppKit
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

        check(
            ChatGPTVoiceLauncher.url.scheme == "https"
                && ChatGPTVoiceLauncher.url.host == "chatgpt.com"
                && ChatGPTVoiceLauncher.url.path == "/",
            "Voice handoff uses only the official ChatGPT URL",
            failures: &failures
        )
        check(
            CompanionLayout.normalizedScale(.nan) == CompanionLayout.defaultAvatarScale,
            "non-finite avatar scale uses the default",
            failures: &failures
        )
        check(
            CompanionLayout.normalizedScale(0.2) == 0.70
                && CompanionLayout.normalizedScale(2.0) == 1.40,
            "avatar scale is clamped to 70–140 percent",
            failures: &failures
        )
        let smallCollapsed = CompanionLayout.collapsedSize(scale: 0.70)
        let largeCollapsed = CompanionLayout.collapsedSize(scale: 1.40)
        check(
            abs(smallCollapsed.width - 119) < 0.001
                && abs(smallCollapsed.height - 133) < 0.001
                && abs(largeCollapsed.width - 238) < 0.001
                && abs(largeCollapsed.height - 266) < 0.001,
            "collapsed panel follows avatar scale",
            failures: &failures
        )
        check(
            CompanionLayout.expandedSize(scale: 0.70) == CompanionLayout.baseExpandedSize
                && CompanionLayout.expandedSize(scale: 1.40).width > CompanionLayout.baseExpandedSize.width
                && CompanionLayout.radialRadius(scale: 1.40) > CompanionLayout.baseRadialRadius,
            "expanded menu gains clearance for a large avatar",
            failures: &failures
        )
        check(
            MenuInactivityPolicy.defaultSeconds == 15
                && MenuInactivityPolicy.normalizedSeconds(1) == 5
                && MenuInactivityPolicy.normalizedSeconds(99) == 60,
            "control menu inactivity timeout defaults and clamps",
            failures: &failures
        )
        let activity = Date(timeIntervalSinceReferenceDate: 100)
        check(
            !MenuInactivityPolicy.shouldClose(
                lastInteraction: activity,
                now: activity.addingTimeInterval(14.99),
                timeoutSeconds: 15
            )
                && MenuInactivityPolicy.shouldClose(
                    lastInteraction: activity,
                    now: activity.addingTimeInterval(15),
                    timeoutSeconds: 15
                ),
            "control menu closes only at the inactivity deadline",
            failures: &failures
        )
        for scale in [0.70, 1.0, 1.40] {
            let size = CompanionLayout.expandedSize(scale: scale)
            let expandedCenter = CGPoint(x: size.width / 2, y: size.height / 2)
            let focusPoint = RadialLayout.point(
                for: .pomodoro,
                center: expandedCenter,
                radius: CompanionLayout.radialRadius(scale: scale)
            )
            let panelCenter = CGPoint(
                x: focusPoint.x,
                y: CompanionLayout.focusPanelCenterY(center: expandedCenter, scale: scale)
            )
            let panelRect = CGRect(
                x: panelCenter.x - CompanionLayout.focusPanelSize.width / 2,
                y: panelCenter.y - CompanionLayout.focusPanelSize.height / 2,
                width: CompanionLayout.focusPanelSize.width,
                height: CompanionLayout.focusPanelSize.height
            )
            let buttonRect = CGRect(x: focusPoint.x - 43, y: focusPoint.y - 34, width: 86, height: 68)
            check(
                CGRect(origin: .zero, size: size).contains(panelRect)
                    && !panelRect.intersects(buttonRect),
                "Focus checklist panel fits without covering its button at \(scale)",
                failures: &failures
            )
        }

        let magnetic = MagneticHoverConfiguration.framerUniversityDefault
        check(
            magnetic.distance == 10
                && magnetic.hoverArea == 10
                && magnetic.smoothing == 50
                && magnetic.damping == 100
                && abs(magnetic.stiffness - 1_025) < 0.001,
            "magnetic hover uses the supplied Framer defaults",
            failures: &failures
        )
        check(
            MagneticHoverMath.mapRange(
                0,
                fromLow: 0,
                fromHigh: 100,
                toLow: 2_000,
                toHigh: 50
            ) == 2_000
                && MagneticHoverMath.mapRange(
                    100,
                    fromLow: 0,
                    fromHigh: 100,
                    toLow: 2_000,
                    toHigh: 50
                ) == 50,
            "magnetic smoothing maps to Framer spring stiffness",
            failures: &failures
        )
        let magneticSize = CGSize(width: 86, height: 68)
        check(
            MagneticHoverMath.offset(
                pointer: CGPoint(x: 43, y: 34),
                size: magneticSize
            ) == .zero
                && MagneticHoverMath.offset(
                    pointer: CGPoint(x: 86, y: 34),
                    size: magneticSize
                ).width == 10,
            "magnetic hover center and edge displacement",
            failures: &failures
        )
        let expandedMagnetic = MagneticHoverMath.offset(
            pointer: CGPoint(x: 96, y: 78),
            size: magneticSize
        )
        check(
            abs(expandedMagnetic.width - 12.325_581) < 0.001
                && abs(expandedMagnetic.height - 12.941_176) < 0.001
                && MagneticHoverMath.offset(
                    pointer: CGPoint(x: 96.01, y: 34),
                    size: magneticSize
                ) == .zero,
            "magnetic hover preserves the supplied expanded hover boundary",
            failures: &failures
        )
        check(
            SpriteAnimation.runningRight.atlasRow == 1
                && SpriteAnimation.runningLeft.atlasRow == 2,
            "directional running rows",
            failures: &failures
        )
        check(
            SpriteAnimation.standardCases.compactMap(\.atlasRow) == Array(0 ... 8),
            "all standard animation rows mapped",
            failures: &failures
        )
        check(
            SpriteAnimation.standardCases.map { $0.durations.count }
                == [7, 8, 8, 4, 5, 8, 6, 6, 6]
                && SpriteAnimation.dancing.atlasRow == nil
                && SpriteAnimation.dancing.durations.count == 8,
            "standard atlas and standalone dance frames are mapped",
            failures: &failures
        )
        check(
            (0 ..< 8).allSatisfy {
                SpriteSheet.shared.frame(animation: .dancing, column: $0)?.size
                    == SpriteSheet.cellSize
            },
            "all eight standalone dance frames resolve at pet cell size",
            failures: &failures
        )
        let motion = AvatarMotionController()
        motion.setMusicPlaying(true)
        check(
            motion.animation == .dancing && motion.isAnimating,
            "active music starts the dance immediately",
            failures: &failures
        )
        motion.setReducedMotion(true)
        check(
            motion.animation == .dancing && !motion.isAnimating,
            "Reduce Motion holds a static dance pose",
            failures: &failures
        )
        motion.setContext(.working)
        check(
            motion.animation == .working && !motion.isAnimating,
            "Focus context overrides music while Reduce Motion is enabled",
            failures: &failures
        )
        motion.setContext(nil)
        check(
            motion.animation == .dancing && !motion.isAnimating,
            "dance resumes after an overriding context ends",
            failures: &failures
        )
        motion.setReducedMotion(false)
        motion.setMusicPlaying(false)
        check(
            motion.animation == .idle && !motion.isAnimating,
            "stopped music returns Joi to idle",
            failures: &failures
        )
        check(SpriteLookDirection.toward(pointer: CGPoint(x: 250, y: 150), from: center)?.index == 0, "gaze points up", failures: &failures)
        check(SpriteLookDirection.toward(pointer: CGPoint(x: 350, y: 250), from: center)?.index == 4, "gaze points right", failures: &failures)
        check(timer.remainingProgress == 1, "Pomodoro progress resets", failures: &failures)

        let music = MusicController(monitorPlayback: false)
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
            MusicController.nowPlayingCommand(for: .previous) == .previous
                && MusicController.nowPlayingCommand(for: .playPause) == .togglePlayPause
                && MusicController.nowPlayingCommand(for: .next) == .next,
            "transport controls target the current Now Playing session first",
            failures: &failures
        )
        check(
            MusicController.nowPlayingFeatureCommands(for: .shuffle) == [.advanceShuffleMode]
                && MusicController.nowPlayingFeatureCommands(for: .favorite)
                    == [.addNowPlayingItemToLibrary, .likeTrack]
                && MusicController.NowPlayingCommand.advanceShuffleMode.rawValue == 6
                && MusicController.NowPlayingCommand.likeTrack.rawValue == 21
                && MusicController.NowPlayingCommand.addNowPlayingItemToLibrary.rawValue == 127,
            "shuffle and favorite use capability-gated Now Playing commands",
            failures: &failures
        )
        _ = MusicController.commandSupport(for: .togglePlayPause)
        check(
            MusicController.accessibilitySettingsURL.scheme == "x-apple.systempreferences",
            "music fallback has an actionable Accessibility settings link",
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
            MusicController.canUseMediaKeyFallback(
                hasActiveOutput: true,
                matchesLastValidatedOwner: false
            )
                && MusicController.canUseMediaKeyFallback(
                    hasActiveOutput: false,
                    matchesLastValidatedOwner: true
                )
                && !MusicController.canUseMediaKeyFallback(
                    hasActiveOutput: false,
                    matchesLastValidatedOwner: false
                ),
            "paused media can resume only for the last validated owner",
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
        let arcCallSamples = [
            MusicController.MediaProcessAudioSample(
                bundleIdentifier: "company.thebrowser.Browser.helper.renderer",
                isRunningOutput: true,
                isRunningInput: false,
                isInputStateKnown: true
            ),
            MusicController.MediaProcessAudioSample(
                bundleIdentifier: "company.thebrowser.Browser",
                isRunningOutput: false,
                isRunningInput: true,
                isInputStateKnown: true
            ),
        ]
        check(
            !MusicController.hasEligibleMediaPlayback(
                samples: arcCallSamples,
                nowPlayingOwnerBundleIdentifier: "company.thebrowser.Browser"
            )
                && MusicController.hasEligibleMediaPlayback(
                    samples: [arcCallSamples[0]],
                    nowPlayingOwnerBundleIdentifier: "company.thebrowser.Browser"
                )
                && !MusicController.hasEligibleMediaPlayback(
                    samples: [arcCallSamples[0]],
                    nowPlayingOwnerBundleIdentifier: "com.apple.Music"
                ),
            "browser-family playback detection rejects calls and owner mismatches",
            failures: &failures
        )
        let firstMiss = MusicController.playbackTransition(
            current: true,
            consecutiveMisses: 0,
            detected: false
        )
        let secondMiss = MusicController.playbackTransition(
            current: firstMiss.isPlaying,
            consecutiveMisses: firstMiss.misses,
            detected: false
        )
        check(
            MusicController.playbackTransition(
                current: false,
                consecutiveMisses: 0,
                detected: true
            ).isPlaying
                && firstMiss.isPlaying
                && !secondMiss.isPlaying,
            "playback starts immediately and stops after two misses",
            failures: &failures
        )
        let detectedMusic = MusicController(
            playbackProbe: { true },
            monitorPlayback: false
        )
        detectedMusic.refreshPlaybackState()
        check(
            detectedMusic.isPlaying,
            "injected playback probe publishes the playing state",
            failures: &failures
        )
        check(music.script(for: .next, player: .music).isEmpty, "transport controls cannot launch a named player", failures: &failures)
        check(music.script(for: .shuffle, player: .spotify) == "tell application \"Spotify\" to set shuffling to not shuffling", "Spotify command", failures: &failures)
        check(music.script(for: .favorite, player: .spotify).isEmpty, "Spotify read-only favorite is not misrepresented", failures: &failures)
        check(
            MusicController.arcSpotifyJavaScript(for: .shuffle)?.contains("control-button-shuffle") == true
                && MusicController.arcSpotifyJavaScript(for: .favorite)?.contains("now-playing-widget") == true
                && MusicController.arcSpotifyJavaScript(for: .favorite)?.contains("add-button") == true
                && MusicController.arcSpotifyJavaScript(for: .favorite)?.contains("playbackState === 'playing'") == true
                && MusicController.arcSpotifyAppleScript(for: .favorite)?.contains(
                    "on error errorMessage number errorNumber"
                ) == true
                && MusicController.arcSpotifyAppleScript(for: .favorite)?.contains(
                    "activeTabCount is not 1 or spotifyPlayingCount is not 1"
                ) == true
                && MusicController.arcSpotifyJavaScript(for: .playPause) == nil,
            "Arc Spotify integration requires unambiguous active playback and explicit feature controls",
            failures: &failures
        )
        var arcScriptCompileError: NSDictionary?
        let arcScriptCompiled = MusicController.arcSpotifyAppleScript(for: .favorite)
            .flatMap(NSAppleScript.init(source:))?
            .compileAndReturnError(&arcScriptCompileError) == true
        check(
            arcScriptCompiled && arcScriptCompileError == nil,
            "Arc Spotify automation script compiles without executing",
            failures: &failures
        )

        let suiteName = "JoiSelfTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let panelTimer = PomodoroTimer(seconds: 1, completionSound: {}, completionNotification: {})
        var voiceOpenCount = 0
        let panelModel = AppModel(
            defaults: defaults,
            pomodoro: panelTimer,
            openChatGPTVoice: {
                voiceOpenCount += 1
                return true
            }
        )
        panelModel.activateVoice()
        check(
            panelModel.activePanel == .voice
                && panelModel.voiceHandoff == .opened
                && voiceOpenCount == 1,
            "Voice opens ChatGPT once without an API key or fake listening state",
            failures: &failures
        )
        panelModel.activateVoice()
        check(
            panelModel.activePanel == .none && voiceOpenCount == 1,
            "second Voice click only closes Joi's local instructions",
            failures: &failures
        )
        var quitCount = 0
        panelModel.onQuit = { quitCount += 1 }
        panelModel.quitJoi()
        check(
            quitCount == 1,
            "avatar context-menu Close Joi requests application termination",
            failures: &failures
        )
        let failedVoiceModel = AppModel(
            defaults: defaults,
            pomodoro: PomodoroTimer(seconds: 1, completionSound: {}, completionNotification: {}),
            openChatGPTVoice: { false }
        )
        failedVoiceModel.activateVoice()
        check(
            failedVoiceModel.voiceHandoff == .failed,
            "failed browser handoff is reported",
            failures: &failures
        )

        var observedScale: Double?
        panelModel.onAvatarScaleChange = { observedScale = $0 }
        panelModel.avatarScale = 1.35
        check(
            observedScale == 1.35 && defaults.double(forKey: "joi.avatarScale") == 1.35,
            "avatar scale callback and persistence",
            failures: &failures
        )
        let reloadedModel = AppModel(
            defaults: defaults,
            pomodoro: PomodoroTimer(seconds: 1, completionSound: {}, completionNotification: {}),
            openChatGPTVoice: { false }
        )
        check(reloadedModel.avatarScale == 1.35, "avatar scale reloads", failures: &failures)
        panelModel.avatarScale = 5
        check(
            panelModel.avatarScale == 1.40
                && defaults.double(forKey: "joi.avatarScale") == 1.40
                && observedScale == 1.40,
            "avatar scale setter clamps, persists, and resizes",
            failures: &failures
        )

        check(
            panelModel.menuAutoCloseSeconds == MenuInactivityPolicy.defaultSeconds,
            "control menu inactivity timeout defaults to 15 seconds",
            failures: &failures
        )
        panelModel.menuAutoCloseSeconds = 35
        let timeoutReloadedModel = AppModel(
            defaults: defaults,
            pomodoro: PomodoroTimer(seconds: 1, completionSound: {}, completionNotification: {}),
            openChatGPTVoice: { false }
        )
        check(
            timeoutReloadedModel.menuAutoCloseSeconds == 35,
            "control menu inactivity timeout persists",
            failures: &failures
        )
        panelModel.isExpanded = true
        panelTimer.reset()
        panelTimer.start()
        check(
            panelModel.closeMenuIfInactive(
                now: Date().addingTimeInterval(TimeInterval(panelModel.menuAutoCloseSeconds + 1))
            )
                && !panelModel.isExpanded
                && panelTimer.state == .running,
            "inactivity closes controls without stopping an active Focus timer",
            failures: &failures
        )
        panelTimer.reset()

        check(!panelModel.addFocusTask("   "), "blank Focus tasks are rejected", failures: &failures)
        for index in 1 ... panelModel.focusTaskLimit {
            check(
                panelModel.addFocusTask("Task \(index)"),
                "Focus task \(index) is accepted",
                failures: &failures
            )
        }
        check(
            !panelModel.addFocusTask("Task 11") && panelModel.focusTasks.count == 10,
            "Focus task list stops at ten",
            failures: &failures
        )
        let firstFocusTask = panelModel.focusTasks[0]
        panelModel.toggleFocusTask(id: firstFocusTask.id)
        let taskReloadedModel = AppModel(
            defaults: defaults,
            pomodoro: PomodoroTimer(seconds: 1, completionSound: {}, completionNotification: {}),
            openChatGPTVoice: { false }
        )
        check(
            taskReloadedModel.focusTasks.count == 10
                && taskReloadedModel.focusTasks[0].id == firstFocusTask.id
                && taskReloadedModel.focusTasks[0].isCompleted,
            "Focus tasks and checkmarks persist",
            failures: &failures
        )
        panelModel.removeFocusTask(id: firstFocusTask.id)
        check(
            panelModel.addFocusTask("Replacement") && panelModel.focusTasks.count == 10,
            "deleting a Focus task frees a slot",
            failures: &failures
        )

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
            print("Joi macOS self-test: all checks passed")
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
