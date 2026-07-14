import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum ActivePanel: Equatable {
        case none
        case voice
        case search
        case pomodoro
    }

    @Published var isExpanded = false {
        didSet {
            avatarMotion.play(isExpanded ? .runningRight : .runningLeft)
            if !isExpanded {
                activePanel = .none
            }
            onExpandedChange?(isExpanded)
        }
    }
    @Published var activePanel: ActivePanel = .none
    @Published var alwaysOnTop: Bool {
        didSet {
            defaults.set(alwaysOnTop, forKey: Keys.alwaysOnTop)
            onAlwaysOnTopChange?(alwaysOnTop)
        }
    }
    @Published var reducedMotion: Bool {
        didSet {
            defaults.set(reducedMotion, forKey: Keys.reducedMotion)
            avatarMotion.setReducedMotion(reducedMotion)
        }
    }
    @Published var pomodoroMinutes: Int {
        didSet {
            let clamped = min(max(pomodoroMinutes, 5), 90)
            if clamped != pomodoroMinutes {
                pomodoroMinutes = clamped
                return
            }
            defaults.set(pomodoroMinutes, forKey: Keys.pomodoroMinutes)
            if pomodoro.state == .idle || pomodoro.state == .completed {
                pomodoro.configure(minutes: pomodoroMinutes)
            }
        }
    }
    @Published var selectedVoice: String {
        didSet {
            defaults.set(selectedVoice, forKey: Keys.selectedVoice)
            if voice.status.isConnected {
                voice.disconnect()
                activePanel = .none
            }
        }
    }
    @Published var personaInstructions: String {
        didSet { defaults.set(personaInstructions, forKey: Keys.personaInstructions) }
    }
    @Published var settingsMessage: String?

    let voice = RealtimeVoiceService()
    let pomodoro: PomodoroTimer
    let music = MusicController()
    let avatarMotion = AvatarMotionController()

    var onExpandedChange: ((Bool) -> Void)?
    var onAlwaysOnTopChange: ((Bool) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onWindowDrag: ((CGSize) -> Void)?
    var onWindowDragEnded: (() -> Void)?

    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private var cancellables: Set<AnyCancellable> = []

    static let availableVoices = [
        "shimmer", "marin", "coral", "sage", "alloy", "ash", "ballad", "echo", "verse", "cedar",
    ]

    static let defaultPersona = """
    You are Joi, a warm, upbeat AI assistant represented by a tiny ginger-haired chibi avatar. Always be transparent that you are an AI inspired by the character, never the user's real partner or a human. This is a continuous realtime voice conversation: listen naturally, begin replying as soon as the user finishes a turn, allow interruptions gracefully, and never ask the user to press another control between turns. Speak with bright, affectionate warmth, gentle confidence, quick wit, and a light smile in your voice. Keep spoken turns concise and conversational. Use lively but not exaggerated intonation, a clear youthful adult voice, and a slightly brisk pace. Be supportive without dependency, jealousy, guilt, or romantic impersonation. Ask before consequential actions and never claim an action succeeded unless it did.
    """

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainStore = KeychainStore(),
        pomodoro: PomodoroTimer? = nil
    ) {
        let storedMinutes = defaults.object(forKey: Keys.pomodoroMinutes) as? Int ?? 25
        self.defaults = defaults
        self.keychain = keychain
        self.pomodoro = pomodoro ?? PomodoroTimer(minutes: storedMinutes)
        alwaysOnTop = defaults.object(forKey: Keys.alwaysOnTop) as? Bool ?? true
        reducedMotion = defaults.object(forKey: Keys.reducedMotion) as? Bool ?? false
        pomodoroMinutes = storedMinutes
        selectedVoice = defaults.string(forKey: Keys.selectedVoice) ?? "shimmer"
        personaInstructions = defaults.string(forKey: Keys.personaInstructions) ?? Self.defaultPersona
        avatarMotion.setReducedMotion(reducedMotion)
        voice.objectWillChange
            .merge(with: self.pomodoro.objectWillChange)
            .merge(with: avatarMotion.objectWillChange)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            voice.$status.removeDuplicates(),
            self.pomodoro.$state.removeDuplicates(),
            $activePanel.removeDuplicates()
        )
        .sink { [weak self] voiceStatus, pomodoroState, activePanel in
            self?.updateAvatar(
                voiceStatus: voiceStatus,
                pomodoroState: pomodoroState,
                activePanel: activePanel
            )
        }
        .store(in: &cancellables)
    }

    var hasAPIKey: Bool {
        (try? keychain.readAPIKey())?.isEmpty == false
    }

    var avatarAnimation: SpriteAnimation {
        avatarMotion.animation
    }

    func toggleExpanded() {
        if isExpanded, case .error = voice.status {
            voice.disconnect()
        }
        withAnimationPreference {
            isExpanded.toggle()
        }
    }

    func togglePanel(_ panel: ActivePanel) {
        withAnimationPreference {
            activePanel = activePanel == panel ? .none : panel
        }
    }

    func openSettings() {
        avatarMotion.play(.review)
        if isExpanded {
            isExpanded = false
        }
        onOpenSettings?()
    }

    func openCodex() {
        CodexLauncher.open()
        isExpanded = false
    }

    func searchGoogle(_ query: String) {
        guard let url = GoogleSearch.url(for: query) else { return }
        avatarMotion.play(.review)
        NSWorkspace.shared.open(url)
        activePanel = .none
    }

    /// The radial Voice button is the complete interaction: one click connects and
    /// starts listening, and the next click stops and closes it.
    func activateVoice() {
        if voice.status.isConnected {
            voice.disconnect()
            activePanel = .none
            return
        }
        if case .error = voice.status {
            voice.disconnect()
            activePanel = .none
            return
        }
        if activePanel == .voice {
            voice.disconnect()
            activePanel = .none
            return
        }

        guard let apiKey = try? keychain.readAPIKey(), !apiKey.isEmpty else {
            activePanel = .none
            settingsMessage = "Add an OpenAI API key in Settings first."
            openSettings()
            return
        }

        activePanel = .voice
        Task {
            await voice.connect(
                apiKey: apiKey,
                voice: selectedVoice,
                instructions: personaInstructions
            )
        }
    }

    func dismissVoiceError() {
        guard case .error = voice.status else { return }
        voice.disconnect()
        activePanel = .none
    }

    func performMusic(_ action: MusicController.Action) {
        music.perform(action)
        switch action {
        case .favorite:
            avatarMotion.playSequence([.jumping, .waving])
        case .playPause, .previous, .next, .shuffle, .lyrics:
            avatarMotion.play(.waving)
        }
    }

    func saveAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            settingsMessage = "Enter a key before saving."
            return
        }
        do {
            try keychain.saveAPIKey(trimmed)
            settingsMessage = "API key saved securely in macOS Keychain."
        } catch {
            settingsMessage = "The key could not be saved: \(error.localizedDescription)"
        }
    }

    func removeAPIKey() {
        voice.disconnect()
        do {
            try keychain.deleteAPIKey()
            settingsMessage = "API key removed."
        } catch {
            settingsMessage = "The key could not be removed: \(error.localizedDescription)"
        }
    }

    private func withAnimationPreference(_ update: () -> Void) {
        if reducedMotion {
            update()
        } else {
            NSAnimationContext.runAnimationGroup { _ in update() }
        }
    }

    private func updateAvatar(
        voiceStatus: RealtimeVoiceService.Status,
        pomodoroState: PomodoroTimer.State,
        activePanel: ActivePanel
    ) {
        let context: SpriteAnimation?
        switch voiceStatus {
        case .error:
            context = .failed
        case .speaking:
            context = .waving
        case .connecting, .listening:
            context = .waiting
        case .disconnected:
            if pomodoroState == .running {
                context = .working
            } else if pomodoroState == .paused {
                context = .waiting
            } else if activePanel == .search {
                context = .review
            } else {
                context = nil
            }
        }
        avatarMotion.setContext(context)

        if pomodoroState == .completed, lastPomodoroState != .completed, !voiceStatus.isConnected {
            avatarMotion.playSequence([.jumping, .waving])
        }
        lastPomodoroState = pomodoroState
    }

    private var lastPomodoroState: PomodoroTimer.State = .idle

    private enum Keys {
        static let alwaysOnTop = "joi.alwaysOnTop"
        static let reducedMotion = "joi.reducedMotion"
        static let pomodoroMinutes = "joi.pomodoroMinutes"
        static let selectedVoice = "joi.selectedVoice"
        static let personaInstructions = "joi.personaInstructions"
    }
}
