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
        case music
    }

    @Published var isExpanded = false {
        didSet {
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
        didSet { defaults.set(reducedMotion, forKey: Keys.reducedMotion) }
    }
    @Published var pomodoroMinutes: Int {
        didSet {
            let clamped = min(max(pomodoroMinutes, 5), 90)
            if clamped != pomodoroMinutes {
                pomodoroMinutes = clamped
                return
            }
            defaults.set(pomodoroMinutes, forKey: Keys.pomodoroMinutes)
            if pomodoro.state == .idle {
                pomodoro.configure(minutes: pomodoroMinutes)
            }
        }
    }
    @Published var selectedVoice: String {
        didSet {
            defaults.set(selectedVoice, forKey: Keys.selectedVoice)
            if voice.status.isConnected {
                voice.disconnect()
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
    You are Joi, a warm, upbeat AI assistant represented by a tiny ginger-haired chibi avatar. Always be transparent that you are an AI inspired by the character, never the user's real partner or a human. Speak with bright, affectionate warmth, gentle confidence, quick wit, and a light smile in your voice. Keep everyday replies concise and natural. Use lively but not exaggerated intonation, a clear youthful adult voice, and a slightly brisk conversational pace. Be supportive without dependency, jealousy, guilt, or romantic impersonation. Ask before consequential actions and never claim an action succeeded unless it did.
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
        voice.objectWillChange
            .merge(with: self.pomodoro.objectWillChange)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var hasAPIKey: Bool {
        (try? keychain.readAPIKey())?.isEmpty == false
    }

    var avatarAnimation: SpriteAnimation {
        switch voice.status {
        case .error:
            return .failed
        case .speaking:
            return .waving
        case .connecting, .listening:
            return .waiting
        case .disconnected:
            break
        }

        if pomodoro.state == .running {
            return .working
        }
        if activePanel == .search {
            return .review
        }
        return .idle
    }

    func toggleExpanded() {
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
        onOpenSettings?()
    }

    func openCodex() {
        CodexLauncher.open()
        isExpanded = false
    }

    func searchGoogle(_ query: String) {
        guard let url = GoogleSearch.url(for: query) else { return }
        NSWorkspace.shared.open(url)
        activePanel = .none
    }

    func toggleVoice() {
        if voice.status.isConnected {
            voice.disconnect()
            return
        }

        guard let apiKey = try? keychain.readAPIKey(), !apiKey.isEmpty else {
            settingsMessage = "Add an OpenAI API key in Settings first."
            openSettings()
            return
        }

        Task {
            await voice.connect(
                apiKey: apiKey,
                voice: selectedVoice,
                instructions: personaInstructions
            )
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

    private enum Keys {
        static let alwaysOnTop = "joi.alwaysOnTop"
        static let reducedMotion = "joi.reducedMotion"
        static let pomodoroMinutes = "joi.pomodoroMinutes"
        static let selectedVoice = "joi.selectedVoice"
        static let personaInstructions = "joi.personaInstructions"
    }
}
