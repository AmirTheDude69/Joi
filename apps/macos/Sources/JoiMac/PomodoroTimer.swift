import AppKit
import Combine
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class PomodoroTimer: ObservableObject {
    typealias CompletionEffect = @MainActor () -> Void

    enum State: Equatable {
        case idle
        case running
        case paused
        case completed
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var remainingSeconds: Int
    private(set) var configuredSeconds: Int
    private let clock = ContinuousClock()
    private let completionSoundEffect: CompletionEffect
    private let completionNotificationEffect: CompletionEffect
    private var timerTask: Task<Void, Never>?
    private var deadline: ContinuousClock.Instant?
    private static var retainedCompletionSound: NSSound?

    init(
        minutes: Int = 25,
        completionSound: CompletionEffect? = nil,
        completionNotification: CompletionEffect? = nil
    ) {
        configuredSeconds = max(1, minutes * 60)
        remainingSeconds = configuredSeconds
        completionSoundEffect = completionSound ?? { Self.playCompletionAlert() }
        completionNotificationEffect = completionNotification ?? { Self.scheduleCompletionNotification() }
    }

    init(
        seconds: Int,
        completionSound: CompletionEffect? = nil,
        completionNotification: CompletionEffect? = nil
    ) {
        configuredSeconds = max(1, seconds)
        remainingSeconds = configuredSeconds
        completionSoundEffect = completionSound ?? { Self.playCompletionAlert() }
        completionNotificationEffect = completionNotification ?? { Self.scheduleCompletionNotification() }
    }

    var formattedRemaining: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    var configuredMinutes: Int {
        max(1, Int(ceil(Double(configuredSeconds) / 60)))
    }

    var remainingProgress: Double {
        guard configuredSeconds > 0 else { return 0 }
        return min(1, max(0, Double(remainingSeconds) / Double(configuredSeconds)))
    }

    func configure(minutes: Int) {
        guard state == .idle || state == .completed else { return }
        deadline = nil
        configuredSeconds = max(1, minutes * 60)
        remainingSeconds = configuredSeconds
        state = .idle
    }

    func start() {
        if state == .completed {
            remainingSeconds = configuredSeconds
        }
        guard state != .running else { return }
        deadline = clock.now.advanced(by: .seconds(remainingSeconds))
        state = .running
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                self.synchronizeToDeadline()
            }
        }
    }

    func pause() {
        guard state == .running else { return }
        synchronizeToDeadline()
        guard state == .running else { return }
        timerTask?.cancel()
        timerTask = nil
        deadline = nil
        state = .paused
    }

    func reset() {
        timerTask?.cancel()
        timerTask = nil
        deadline = nil
        remainingSeconds = configuredSeconds
        state = .idle
    }

    func tick(notifyOnCompletion: Bool = true) {
        guard state == .running else { return }
        remainingSeconds = max(0, remainingSeconds - 1)
        guard remainingSeconds == 0 else { return }
        complete(notifyOnCompletion: notifyOnCompletion)
    }

    private func synchronizeToDeadline(notifyOnCompletion: Bool = true) {
        guard state == .running, let deadline else { return }
        let duration = clock.now.duration(to: deadline).components
        let exactSeconds = Double(duration.seconds)
            + Double(duration.attoseconds) / 1_000_000_000_000_000_000
        remainingSeconds = max(
            0,
            Int(ceil(exactSeconds))
        )
        guard remainingSeconds == 0 else { return }
        complete(notifyOnCompletion: notifyOnCompletion)
    }

    private func complete(notifyOnCompletion: Bool) {
        timerTask?.cancel()
        timerTask = nil
        deadline = nil
        state = .completed
        completionSoundEffect()
        if notifyOnCompletion {
            completionNotificationEffect()
        }
    }

    private static func playCompletionAlert() {
        let namedCandidates = ["Glass", "Hero", "Ping"]
        for name in namedCandidates {
            guard let sound = NSSound(named: NSSound.Name(name)) else { continue }
            retainedCompletionSound = sound
            sound.stop()
            if sound.play() { return }
        }

        let fileCandidates = namedCandidates.map { "/System/Library/Sounds/\($0).aiff" }
        for path in fileCandidates where FileManager.default.fileExists(atPath: path) {
            guard let sound = NSSound(contentsOfFile: path, byReference: true) else { continue }
            retainedCompletionSound = sound
            if sound.play() { return }
        }

        // The system alert sound is the final always-available AppKit fallback.
        NSSound.beep()
    }

    private nonisolated static func scheduleCompletionNotification() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                enqueueCompletionNotification(on: center)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    enqueueCompletionNotification(on: center)
                }
            case .denied:
                // The immediate AppKit alert still fires; respect the user's choice
                // instead of trying to bypass notification permissions.
                break
            @unknown default:
                break
            }
        }
    }

    private nonisolated static func enqueueCompletionNotification(on center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = "Joi says: focus block complete!"
        content.body = "Lovely work. Stretch, hydrate, and choose your next step."
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
