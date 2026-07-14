import AppKit
import Combine
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class PomodoroTimer: ObservableObject {
    enum State: Equatable {
        case idle
        case running
        case paused
        case completed
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var remainingSeconds: Int
    private(set) var configuredSeconds: Int
    private var timerTask: Task<Void, Never>?

    init(minutes: Int = 25) {
        configuredSeconds = max(1, minutes * 60)
        remainingSeconds = configuredSeconds
    }

    init(seconds: Int) {
        configuredSeconds = max(1, seconds)
        remainingSeconds = configuredSeconds
    }

    var formattedRemaining: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    func configure(minutes: Int) {
        guard state == .idle || state == .completed else { return }
        configuredSeconds = max(1, minutes * 60)
        remainingSeconds = configuredSeconds
        state = .idle
    }

    func start() {
        if state == .completed {
            remainingSeconds = configuredSeconds
        }
        guard state != .running else { return }
        state = .running
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    func pause() {
        guard state == .running else { return }
        timerTask?.cancel()
        timerTask = nil
        state = .paused
    }

    func reset() {
        timerTask?.cancel()
        timerTask = nil
        remainingSeconds = configuredSeconds
        state = .idle
    }

    func tick(notifyOnCompletion: Bool = true) {
        guard state == .running else { return }
        remainingSeconds = max(0, remainingSeconds - 1)
        guard remainingSeconds == 0 else { return }
        timerTask?.cancel()
        timerTask = nil
        state = .completed
        NSSound(named: "Glass")?.play()
        if notifyOnCompletion {
            notifyCompletion()
        }
    }

    private func notifyCompletion() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Joi says: focus block complete!"
            content.body = "Lovely work. Stretch, hydrate, and choose your next step."
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
