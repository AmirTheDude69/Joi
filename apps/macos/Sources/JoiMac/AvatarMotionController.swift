import Combine
import Foundation

/// Coordinates semantic actions with all sprite rows without leaving any short
/// gesture on an artificial infinite loop.
@MainActor
final class AvatarMotionController: ObservableObject {
    @Published private(set) var animation: SpriteAnimation = .idle
    @Published private(set) var isAnimating = false

    private var contextAnimation: SpriteAnimation?
    private var contextTask: Task<Void, Never>?
    private var transientTask: Task<Void, Never>?
    private var transientToken: UUID?
    private var ambientTask: Task<Void, Never>?
    private var ambientIndex = 0
    private var contextIndex = 0
    private var userReducedMotion = false
    private var systemReducedMotion = false

    private let ambientSequence: [SpriteAnimation] = [
        .idle, .waving, .idle, .review, .idle, .waiting, .idle, .jumping,
    ]

    init() {
        ambientTask = Task { [weak self] in
            await self?.runAmbientLoop()
        }
    }

    var allowsGazeTracking: Bool {
        !isReducedMotionEnabled
            && contextAnimation == nil
            && transientToken == nil
            && animation == .idle
            && !isAnimating
    }

    var isReducedMotionEnabled: Bool {
        userReducedMotion || systemReducedMotion
    }

    func setReducedMotion(_ enabled: Bool) {
        userReducedMotion = enabled
        applyReducedMotionState()
    }

    func setSystemReducedMotion(_ enabled: Bool) {
        systemReducedMotion = enabled
        applyReducedMotionState()
    }

    /// Persistent states use one contextual cycle, one idle cycle, then a quiet
    /// hold before the next varied gesture. This keeps long focus/listening states
    /// expressive without repeating a sub-second strip forever.
    func setContext(_ animation: SpriteAnimation?) {
        guard contextAnimation != animation else { return }
        contextAnimation = animation
        cancelTransient()
        cancelContext()
        guard let animation else {
            self.animation = .idle
            isAnimating = false
            return
        }
        if isReducedMotionEnabled {
            self.animation = animation
            isAnimating = false
        } else {
            startContextLoop(animation)
        }
    }

    func play(_ animation: SpriteAnimation, cycles: Int = 1) {
        playSequence(Array(repeating: animation, count: max(1, cycles)))
    }

    func playSequence(_ animations: [SpriteAnimation]) {
        guard contextAnimation == nil, !animations.isEmpty else { return }
        cancelTransient()
        let token = UUID()
        transientToken = token
        transientTask = Task { [weak self] in
            guard let self else { return }
            for animation in animations {
                guard !Task.isCancelled, self.transientToken == token, self.contextAnimation == nil else { return }
                self.animation = animation
                self.isAnimating = !self.isReducedMotionEnabled
                let duration = self.isReducedMotionEnabled ? 0.35 : animation.cycleDuration
                try? await Task.sleep(for: .seconds(duration))
            }
            guard !Task.isCancelled, self.transientToken == token else { return }
            self.transientToken = nil
            self.transientTask = nil
            self.animation = self.contextAnimation ?? .idle
            self.isAnimating = false
        }
    }

    private func startContextLoop(_ context: SpriteAnimation) {
        contextTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.contextAnimation == context {
                let variants = self.contextVariants(for: context)
                let gesture = variants[self.contextIndex % variants.count]
                self.contextIndex += 1

                self.animation = gesture
                self.isAnimating = true
                try? await Task.sleep(for: .seconds(gesture.cycleDuration))
                guard !Task.isCancelled, self.contextAnimation == context else { return }

                self.animation = .idle
                self.isAnimating = true
                try? await Task.sleep(for: .seconds(SpriteAnimation.idle.cycleDuration))
                guard !Task.isCancelled, self.contextAnimation == context else { return }

                self.isAnimating = false
                try? await Task.sleep(for: .seconds(self.contextRest(for: context)))
            }
        }
    }

    private func contextVariants(for context: SpriteAnimation) -> [SpriteAnimation] {
        switch context {
        case .working:
            [.working, .review]
        case .waiting:
            [.waiting, .review]
        case .waving:
            [.waving, .review]
        case .review:
            [.review, .waiting]
        case .failed:
            [.failed]
        case .idle, .runningRight, .runningLeft, .jumping:
            [context]
        }
    }

    private func contextRest(for context: SpriteAnimation) -> Double {
        switch context {
        case .waving:
            Double.random(in: 1.5 ... 2.8)
        case .waiting:
            Double.random(in: 3.0 ... 5.0)
        case .working:
            Double.random(in: 4.0 ... 7.0)
        case .review:
            Double.random(in: 4.0 ... 6.5)
        case .failed:
            Double.random(in: 6.0 ... 9.0)
        case .idle, .runningRight, .runningLeft, .jumping:
            Double.random(in: 3.0 ... 5.0)
        }
    }

    private func applyReducedMotionState() {
        cancelTransient()
        cancelContext()
        if let contextAnimation {
            if isReducedMotionEnabled {
                animation = contextAnimation
                isAnimating = false
            } else {
                startContextLoop(contextAnimation)
            }
        } else {
            animation = .idle
            isAnimating = false
        }
    }

    private func cancelTransient() {
        transientTask?.cancel()
        transientTask = nil
        transientToken = nil
    }

    private func cancelContext() {
        contextTask?.cancel()
        contextTask = nil
    }

    private func runAmbientLoop() async {
        while !Task.isCancelled {
            let delay = Double.random(in: 4.5 ... 8.0)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled,
                  contextAnimation == nil,
                  transientToken == nil,
                  !isReducedMotionEnabled
            else { continue }
            let next = ambientSequence[ambientIndex % ambientSequence.count]
            ambientIndex += 1
            play(next)
        }
    }
}
