import AppKit
import SwiftUI

struct FloatingCompanionView: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""

    private let expandedSize = CGSize(width: 500, height: 500)
    private let radialRadius: CGFloat = 170

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                if model.isExpanded {
                    expandedBackdrop(center: center)
                    radialActions(center: center)
                    activePanel(center: center)
                }

                avatar
                    .position(center)
            }
        }
        .frame(
            width: model.isExpanded ? expandedSize.width : 170,
            height: model.isExpanded ? expandedSize.height : 190
        )
        .animation(model.reducedMotion ? nil : .spring(response: 0.34, dampingFraction: 0.76), value: model.isExpanded)
        .animation(model.reducedMotion ? nil : .easeInOut(duration: 0.18), value: model.activePanel)
    }

    private var avatar: some View {
        VStack(spacing: -5) {
            AnimatedSpriteView(animation: model.avatarAnimation, reducedMotion: model.reducedMotion)
                .frame(width: 138, height: 150)
                .contentShape(Rectangle())
                .onTapGesture { model.toggleExpanded() }
                .gesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .global)
                        .onChanged { model.onWindowDrag?($0.translation) }
                        .onEnded { _ in model.onWindowDragEnded?() }
                )
                .accessibilityLabel(model.isExpanded ? "Close Joi controls" : "Open Joi controls")
                .accessibilityAddTraits(.isButton)
                .shadow(color: Color.orange.opacity(0.22), radius: 14, y: 8)

            Capsule()
                .fill(.black.opacity(0.12))
                .frame(width: 68, height: 12)
                .blur(radius: 4)
        }
    }

    @ViewBuilder
    private func expandedBackdrop(center: CGPoint) -> some View {
        Circle()
            .stroke(Color.orange.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [4, 7]))
            .frame(width: radialRadius * 2, height: radialRadius * 2)
            .position(center)
            .allowsHitTesting(false)
        Circle()
            .stroke(Color.white.opacity(0.16), lineWidth: 1)
            .frame(width: radialRadius * 2 + 8, height: radialRadius * 2 + 8)
            .position(center)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func radialActions(center: CGPoint) -> some View {
        ForEach(RadialAction.allCases) { action in
            if !isReplacedByActivePanel(action) {
                RadialActionButton(
                    action: action,
                    isActive: panel(for: action) != .none && panel(for: action) == model.activePanel,
                    handler: { handle(action) }
                )
                .position(RadialLayout.point(for: action, center: center, radius: radialRadius))
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func activePanel(center: CGPoint) -> some View {
        switch model.activePanel {
        case .voice:
            VoiceAssistantPanel(model: model)
                .position(RadialLayout.point(for: .voice, center: center, radius: radialRadius))
        case .search:
            QuickSearchPanel(text: $searchText) { query in
                model.searchGoogle(query)
                searchText = ""
            }
            .position(RadialLayout.point(for: .search, center: center, radius: radialRadius))
        case .pomodoro:
            PomodoroPanel(timer: model.pomodoro, minutes: model.pomodoroMinutes)
                .position(RadialLayout.point(for: .pomodoro, center: center, radius: radialRadius))
        case .music:
            MusicClusterView(controller: model.music)
                .position(RadialLayout.point(for: .music, center: center, radius: radialRadius))
        case .none:
            EmptyView()
        }
    }

    private func handle(_ action: RadialAction) {
        switch action {
        case .voice:
            model.togglePanel(.voice)
        case .search:
            model.togglePanel(.search)
        case .pomodoro:
            model.togglePanel(.pomodoro)
            if model.pomodoro.state == .idle {
                model.pomodoro.start()
            }
        case .settings:
            model.openSettings()
        case .codex:
            model.openCodex()
        case .music:
            model.togglePanel(.music)
        }
    }

    private func panel(for action: RadialAction) -> AppModel.ActivePanel {
        switch action {
        case .voice: .voice
        case .search: .search
        case .pomodoro: .pomodoro
        case .music: .music
        case .settings, .codex: .none
        }
    }

    private func isReplacedByActivePanel(_ action: RadialAction) -> Bool {
        panel(for: action) != .none && panel(for: action) == model.activePanel
    }
}

private struct AnimatedSpriteView: View {
    let animation: SpriteAnimation
    let reducedMotion: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @State private var frame = 0

    var body: some View {
        Group {
            if let image = SpriteSheet.shared.frame(row: animation.row, column: frame) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "sparkles")
                    .resizable()
                    .scaledToFit()
                    .padding(48)
                    .foregroundStyle(.orange)
            }
        }
        .task(id: "\(animation.rawValue)-\(reducedMotion)-\(systemReducedMotion)") {
            frame = 0
            guard !reducedMotion, !systemReducedMotion else { return }
            while !Task.isCancelled {
                let duration = animation.durations[frame % animation.durations.count]
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                frame = (frame + 1) % animation.durations.count
            }
        }
    }
}

private struct RadialActionButton: View {
    let action: RadialAction
    let isActive: Bool
    let handler: () -> Void

    var body: some View {
        Button(action: handler) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? Color.white : Color.primary.opacity(0.84))
            .frame(width: 66, height: 66)
            .background {
                Circle()
                    .fill(isActive ? AnyShapeStyle(Color.orange.gradient) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
            }
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var icon: String {
        switch action {
        case .voice: "waveform.circle.fill"
        case .search: "magnifyingglass"
        case .pomodoro: "timer"
        case .settings: "gearshape.fill"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .music: "music.note"
        }
    }

    private var label: String {
        switch action {
        case .voice: "Voice"
        case .search: "Search"
        case .pomodoro: "Focus"
        case .settings: "Settings"
        case .codex: "Codex"
        case .music: "Music"
        }
    }

    private var help: String {
        switch action {
        case .voice: "OpenAI voice assistant"
        case .search: "Quick Google search"
        case .pomodoro: "Pomodoro timer"
        case .settings: "Joi settings"
        case .codex: "Open or switch to Codex"
        case .music: "Music controls"
        }
    }
}

private struct QuickSearchPanel: View {
    @Binding var text: String
    let onSubmit: (String) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search Google", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { onSubmit(text) }
            Button { onSubmit(text) } label: {
                Image(systemName: "arrow.right.circle.fill")
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 13)
        .frame(width: 224, height: 48)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.7)))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
        .onAppear { focused = true }
    }
}

private struct VoiceAssistantPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 9) {
                Image(systemName: model.voice.status == .speaking ? "waveform" : "mic.fill")
                    .symbolEffect(.variableColor.iterative, isActive: model.voice.status.isConnected)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.voice.status.label)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("\(RealtimeVoiceService.model) · \(model.selectedVoice)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: model.toggleVoice) {
                    Image(systemName: model.voice.status.isConnected ? "stop.fill" : "play.fill")
                        .frame(width: 28, height: 28)
                        .background(model.voice.status.isConnected ? Color.red : Color.orange, in: Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            if !model.voice.assistantTranscript.isEmpty {
                Text(model.voice.assistantTranscript)
                    .font(.caption)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if case let .error(message) = model.voice.status {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(width: 270)
        .frame(minHeight: 76)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.72)))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
    }
}

private struct PomodoroPanel: View {
    @ObservedObject var timer: PomodoroTimer
    let minutes: Int

    var body: some View {
        VStack(spacing: 7) {
            Text(timer.formattedRemaining)
                .font(.system(size: 25, weight: .bold, design: .rounded).monospacedDigit())
            HStack(spacing: 10) {
                Button(action: toggle) {
                    Image(systemName: timer.state == .running ? "pause.fill" : "play.fill")
                }
                Button(action: timer.reset) {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
            .buttonStyle(.borderless)
            Text(timer.state == .completed ? "Beautiful focus!" : "\(minutes)-minute focus")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(11)
        .frame(width: 158, height: 104)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.7)))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
    }

    private func toggle() {
        if timer.state == .running {
            timer.pause()
        } else {
            timer.start()
        }
    }
}

private struct MusicClusterView: View {
    @ObservedObject var controller: MusicController

    private let actions: [(MusicController.Action, String, String)] = [
        (.previous, "backward.fill", "Previous"),
        (.playPause, "playpause.fill", "Play or pause"),
        (.next, "forward.fill", "Next"),
        (.favorite, "heart.fill", "Favorite"),
        (.shuffle, "shuffle", "Shuffle"),
        (.lyrics, "quote.bubble.fill", "Lyrics"),
    ]

    var body: some View {
        VStack(spacing: 4) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(39), spacing: 7), count: 3), spacing: 7) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, item in
                    Button { controller.perform(item.0) } label: {
                        Image(systemName: item.1)
                            .frame(width: 34, height: 30)
                            .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .help(item.2)
                    .accessibilityLabel(item.2)
                }
            }
            if let message = controller.lastMessage {
                Text(message)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(9)
        .frame(width: 158)
        .frame(minHeight: 84)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.72)))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
    }
}
