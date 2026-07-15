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

    enum VoiceHandoff: Equatable {
        case ready
        case opened
        case failed
    }

    @Published var isExpanded = false {
        didSet {
            guard oldValue != isExpanded else { return }
            if isExpanded {
                avatarMotion.play(.runningRight)
                lastMenuInteraction = Date()
                startMenuAutoCloseLoop()
            } else {
                cancelMenuAutoCloseLoop()
                activePanel = .none
                avatarMotion.play(.runningLeft)
            }
            onExpandedChange?(isExpanded)
        }
    }
    @Published var activePanel: ActivePanel = .none {
        didSet {
            if oldValue != activePanel {
                noteMenuInteraction()
            }
        }
    }
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
    @Published var avatarScale: Double {
        didSet {
            let normalized = CompanionLayout.normalizedScale(avatarScale)
            if normalized != avatarScale {
                avatarScale = normalized
            }
            defaults.set(normalized, forKey: Keys.avatarScale)
            onAvatarScaleChange?(normalized)
        }
    }
    @Published var menuAutoCloseSeconds: Int {
        didSet {
            let normalized = MenuInactivityPolicy.normalizedSeconds(menuAutoCloseSeconds)
            if normalized != menuAutoCloseSeconds {
                menuAutoCloseSeconds = normalized
            }
            defaults.set(normalized, forKey: Keys.menuAutoCloseSeconds)
            if isExpanded {
                lastMenuInteraction = Date()
                startMenuAutoCloseLoop()
            }
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
    @Published var settingsMessage: String?
    @Published private(set) var voiceHandoff: VoiceHandoff = .ready
    @Published private(set) var focusTasks: [FocusTaskItem]

    let pomodoro: PomodoroTimer
    let music = MusicController()
    let avatarMotion = AvatarMotionController()
    let focusTaskLimit = 10

    var onExpandedChange: ((Bool) -> Void)?
    var onAvatarScaleChange: ((Double) -> Void)?
    var onAlwaysOnTopChange: ((Bool) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?
    var onWindowDrag: ((CGSize) -> Void)?
    var onWindowDragEnded: (() -> Void)?

    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private let openChatGPTVoiceURL: @MainActor () -> Bool
    private var cancellables: Set<AnyCancellable> = []
    private var menuAutoCloseTask: Task<Void, Never>?
    private var lastMenuInteraction = Date.distantPast

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainStore = KeychainStore(),
        pomodoro: PomodoroTimer? = nil,
        openChatGPTVoice: @escaping @MainActor () -> Bool = ChatGPTVoiceLauncher.open
    ) {
        let storedMinutes = defaults.object(forKey: Keys.pomodoroMinutes) as? Int ?? 25
        let storedScale = defaults.object(forKey: Keys.avatarScale) as? Double
            ?? CompanionLayout.defaultAvatarScale
        let storedMenuAutoCloseSeconds = defaults.object(
            forKey: Keys.menuAutoCloseSeconds
        ) as? Int ?? MenuInactivityPolicy.defaultSeconds
        self.defaults = defaults
        self.keychain = keychain
        openChatGPTVoiceURL = openChatGPTVoice
        self.pomodoro = pomodoro ?? PomodoroTimer(minutes: storedMinutes)
        focusTasks = Self.loadFocusTasks(from: defaults)
        alwaysOnTop = defaults.object(forKey: Keys.alwaysOnTop) as? Bool ?? true
        reducedMotion = defaults.object(forKey: Keys.reducedMotion) as? Bool ?? false
        avatarScale = CompanionLayout.normalizedScale(storedScale)
        menuAutoCloseSeconds = MenuInactivityPolicy.normalizedSeconds(
            storedMenuAutoCloseSeconds
        )
        pomodoroMinutes = storedMinutes
        avatarMotion.setReducedMotion(reducedMotion)
        self.pomodoro.objectWillChange
            .merge(with: avatarMotion.objectWillChange)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            self.pomodoro.$state.removeDuplicates(),
            $activePanel.removeDuplicates()
        )
        .sink { [weak self] pomodoroState, activePanel in
            self?.updateAvatar(
                pomodoroState: pomodoroState,
                activePanel: activePanel
            )
        }
        .store(in: &cancellables)
    }

    var avatarAnimation: SpriteAnimation {
        avatarMotion.animation
    }

    func toggleExpanded() {
        withAnimationPreference {
            isExpanded.toggle()
        }
    }

    func noteMenuInteraction() {
        lastMenuInteraction = Date()
        guard isExpanded, menuAutoCloseTask == nil else { return }
        startMenuAutoCloseLoop()
    }

    @discardableResult
    func closeMenuIfInactive(now: Date = Date()) -> Bool {
        guard isExpanded,
              MenuInactivityPolicy.shouldClose(
                  lastInteraction: lastMenuInteraction,
                  now: now,
                  timeoutSeconds: menuAutoCloseSeconds
              )
        else { return false }
        cancelMenuAutoCloseLoop()
        withAnimationPreference {
            isExpanded = false
        }
        return true
    }

    func togglePanel(_ panel: ActivePanel) {
        withAnimationPreference {
            activePanel = activePanel == panel ? .none : panel
        }
    }

    func openSettings() {
        if isExpanded {
            isExpanded = false
        }
        avatarMotion.play(.review)
        onOpenSettings?()
    }

    func openCodex() {
        CodexLauncher.open()
        isExpanded = false
    }

    func quitJoi() {
        onQuit?()
    }

    func searchGoogle(_ query: String) {
        guard let url = GoogleSearch.url(for: query) else { return }
        NSWorkspace.shared.open(url)
        activePanel = .none
        avatarMotion.play(.review)
    }

    /// ChatGPT's web voice UI requires its own explicit Voice-button click and
    /// browser microphone permission. Joi opens the official site and explains
    /// that handoff without pretending it can observe the external session.
    func activateVoice() {
        if activePanel == .voice {
            activePanel = .none
            return
        }
        activePanel = .voice
        applyVoiceHandoff(openChatGPTVoiceURL())
    }

    func openChatGPTVoiceAgain() {
        applyVoiceHandoff(openChatGPTVoiceURL())
    }

    func openChatGPTVoiceFromSettings() {
        settingsMessage = openChatGPTVoiceURL()
            ? "ChatGPT opened. Select its Voice icon and allow microphone access."
            : "ChatGPT could not be opened in your default browser."
    }

    func dismissVoiceHandoff() {
        activePanel = .none
    }

    func performMusic(_ action: MusicController.Action) {
        noteMenuInteraction()
        guard music.perform(action) else {
            avatarMotion.play(.failed)
            return
        }
        switch action {
        case .favorite:
            avatarMotion.playSequence([.jumping, .waving])
        case .playPause, .previous, .next, .shuffle, .lyrics:
            avatarMotion.play(.waving)
        }
    }

    @discardableResult
    func addFocusTask(_ title: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, focusTasks.count < focusTaskLimit else {
            return false
        }
        focusTasks.append(FocusTaskItem(title: normalized))
        persistFocusTasks()
        noteMenuInteraction()
        avatarMotion.play(.review)
        return true
    }

    func toggleFocusTask(id: FocusTaskItem.ID) {
        guard let index = focusTasks.firstIndex(where: { $0.id == id }) else {
            return
        }
        focusTasks[index].isCompleted.toggle()
        persistFocusTasks()
        noteMenuInteraction()
        if focusTasks[index].isCompleted {
            let allComplete = !focusTasks.isEmpty && focusTasks.allSatisfy(\.isCompleted)
            avatarMotion.playSequence(allComplete ? [.jumping, .waving] : [.waving])
        }
    }

    func removeFocusTask(id: FocusTaskItem.ID) {
        focusTasks.removeAll { $0.id == id }
        persistFocusTasks()
        noteMenuInteraction()
    }

    func removeLegacyAPIKey() {
        do {
            try keychain.deleteAPIKey()
            settingsMessage = "The unused legacy API key was removed from Keychain."
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

    private func applyVoiceHandoff(_ opened: Bool) {
        voiceHandoff = opened ? .opened : .failed
        if opened {
            avatarMotion.setContext(.waiting)
        } else {
            avatarMotion.setContext(nil)
            avatarMotion.play(.failed)
        }
    }

    private func startMenuAutoCloseLoop() {
        cancelMenuAutoCloseLoop()
        guard isExpanded else { return }
        menuAutoCloseTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let timeout = TimeInterval(self.menuAutoCloseSeconds)
                let elapsed = Date().timeIntervalSince(self.lastMenuInteraction)
                let remaining = max(0.05, timeout - elapsed)
                do {
                    try await Task.sleep(for: .seconds(remaining))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                if self.closeMenuIfInactive() {
                    return
                }
            }
        }
    }

    private func cancelMenuAutoCloseLoop() {
        menuAutoCloseTask?.cancel()
        menuAutoCloseTask = nil
    }

    private func persistFocusTasks() {
        guard let data = try? JSONEncoder().encode(focusTasks) else { return }
        defaults.set(data, forKey: Keys.focusTasks)
    }

    private static func loadFocusTasks(from defaults: UserDefaults) -> [FocusTaskItem] {
        guard let data = defaults.data(forKey: Keys.focusTasks),
              let decoded = try? JSONDecoder().decode([FocusTaskItem].self, from: data)
        else { return [] }
        return decoded
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(10)
            .map { $0 }
    }

    private func updateAvatar(
        pomodoroState: PomodoroTimer.State,
        activePanel: ActivePanel
    ) {
        let context: SpriteAnimation?
        if activePanel == .voice {
            context = .waiting
        } else {
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

        if pomodoroState == .completed, lastPomodoroState != .completed {
            avatarMotion.playSequence([.jumping, .waving])
        }
        lastPomodoroState = pomodoroState
    }

    private var lastPomodoroState: PomodoroTimer.State = .idle

    private enum Keys {
        static let alwaysOnTop = "joi.alwaysOnTop"
        static let reducedMotion = "joi.reducedMotion"
        static let avatarScale = "joi.avatarScale"
        static let menuAutoCloseSeconds = "joi.menuAutoCloseSeconds"
        static let pomodoroMinutes = "joi.pomodoroMinutes"
        static let focusTasks = "joi.focusTasks"
    }
}
