import AppKit
import SwiftUI

struct FloatingCompanionView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @State private var searchText = ""
    @State private var gazeDirection: SpriteLookDirection?

    private let expandedSize = CGSize(width: 560, height: 520)
    private let radialRadius: CGFloat = 190

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                if model.isExpanded {
                    activePanel(center: center)
                        .zIndex(1)
                    radialActions(center: center)
                        .zIndex(2)
                }

                avatar
                    .position(center)
                    .zIndex(3)
            }
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    gazeDirection = model.avatarMotion.allowsGazeTracking
                        ? SpriteLookDirection.toward(pointer: location, from: center)
                        : nil
                case .ended:
                    gazeDirection = nil
                }
            }
        }
        .frame(
            width: model.isExpanded ? expandedSize.width : 170,
            height: model.isExpanded ? expandedSize.height : 190
        )
        .animation(effectiveReducedMotion ? nil : .spring(response: 0.34, dampingFraction: 0.78), value: model.isExpanded)
        .animation(effectiveReducedMotion ? nil : .easeInOut(duration: 0.18), value: model.activePanel)
        .onAppear { model.avatarMotion.setSystemReducedMotion(systemReducedMotion) }
        .onChange(of: systemReducedMotion) { _, enabled in
            model.avatarMotion.setSystemReducedMotion(enabled)
        }
    }

    private var avatar: some View {
        VStack(spacing: -5) {
            AnimatedSpriteView(
                animation: model.avatarAnimation,
                lookDirection: model.avatarMotion.allowsGazeTracking ? gazeDirection : nil,
                playsAnimation: model.avatarMotion.isAnimating,
                reducedMotion: model.reducedMotion
            )
            .frame(width: 138, height: 150)
            .contentShape(Rectangle())
            .onTapGesture { model.toggleExpanded() }
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    // The AppKit window controller anchors this first translation to
                    // the screen-space mouse origin, then follows NSEvent.mouseLocation.
                    // Keeping the SwiftUI gesture as a signal avoids feedback from the
                    // window moving underneath this view.
                    .onChanged { model.onWindowDrag?($0.translation) }
                    .onEnded { _ in model.onWindowDragEnded?() }
            )
            .accessibilityLabel(model.isExpanded ? "Close Joi controls" : "Open Joi controls")
            .accessibilityAddTraits(.isButton)
            .shadow(color: Color.black.opacity(0.24), radius: 10, y: 6)
            .overlay(alignment: .top) {
                if !model.isExpanded, model.voice.status.isConnected {
                    Label(
                        model.voice.status == .speaking ? "Speaking" : "Listening",
                        systemImage: model.voice.status == .speaking ? "waveform" : "mic.fill"
                    )
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .shadow(color: .black.opacity(0.9), radius: 2, y: 1)
                    .offset(y: -4)
                }
            }

            Capsule()
                .fill(.black.opacity(0.12))
                .frame(width: 68, height: 12)
                .blur(radius: 4)
        }
    }

    @ViewBuilder
    private func radialActions(center: CGPoint) -> some View {
        ForEach(RadialAction.allCases) { action in
            if shouldShow(action) {
                Group {
                    if action == .music {
                        MusicHoneycombCluster(
                            controller: model.music,
                            onAction: model.performMusic
                        )
                    } else {
                        FramelessActionButton(
                            action: action,
                            icon: icon(for: action),
                            label: label(for: action),
                            isActive: isActive(action),
                            handler: { handle(action) }
                        )
                    }
                }
                .position(RadialLayout.point(for: action, center: center, radius: radialRadius))
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func activePanel(center: CGPoint) -> some View {
        switch model.activePanel {
        case .voice:
            VoiceStatusPanel(model: model)
                .position(x: center.x, y: center.y - 127)
        case .search:
            QuickSearchPanel(text: $searchText) { query in
                model.searchGoogle(query)
                searchText = ""
            }
            .position(x: center.x + 105, y: center.y - 155)
        case .pomodoro:
            PomodoroPanel(model: model)
                .position(x: center.x + 165, y: center.y - 45)
        case .none:
            EmptyView()
        }
    }

    private func handle(_ action: RadialAction) {
        switch action {
        case .voice:
            model.activateVoice()
        case .search:
            model.togglePanel(.search)
        case .pomodoro:
            model.togglePanel(.pomodoro)
        case .settings:
            model.openSettings()
        case .codex:
            model.openCodex()
        case .music:
            break
        }
    }

    private func isActive(_ action: RadialAction) -> Bool {
        switch action {
        case .voice:
            model.activePanel == .voice || model.voice.status.isConnected
        case .search:
            model.activePanel == .search
        case .pomodoro:
            model.activePanel == .pomodoro || model.pomodoro.state == .running
        case .settings, .codex, .music:
            false
        }
    }

    private func shouldShow(_ action: RadialAction) -> Bool {
        switch model.activePanel {
        case .none:
            true
        case .voice:
            action == .voice
        case .search:
            action == .search
        case .pomodoro:
            action == .pomodoro
        }
    }

    private func icon(for action: RadialAction) -> String {
        switch action {
        case .voice:
            switch model.voice.status {
            case .speaking: "waveform"
            case .connecting: "ellipsis"
            case .listening: "mic.fill"
            case .disconnected, .error: "waveform.badge.mic"
            }
        case .search: "magnifyingglass"
        case .pomodoro: "timer"
        case .settings: "gearshape.fill"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .music: "music.note"
        }
    }

    private func label(for action: RadialAction) -> String {
        switch action {
        case .voice:
            switch model.voice.status {
            case .connecting: "Connecting"
            case .listening: "Listening"
            case .speaking: "Speaking"
            case .error: "Voice error"
            case .disconnected: "Voice"
            }
        case .search: "Search"
        case .pomodoro: "Focus"
        case .settings: "Settings"
        case .codex: "Codex"
        case .music: "Music"
        }
    }

    private var effectiveReducedMotion: Bool {
        model.reducedMotion || systemReducedMotion
    }
}

private struct AnimatedSpriteView: View {
    let animation: SpriteAnimation
    let lookDirection: SpriteLookDirection?
    let playsAnimation: Bool
    let reducedMotion: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @State private var frame = 0

    var body: some View {
        Group {
            if let image = currentImage {
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
        .task(id: "\(animation.rawValue)-\(lookDirection?.index ?? -1)-\(playsAnimation)-\(reducedMotion)-\(systemReducedMotion)") {
            frame = 0
            guard lookDirection == nil, playsAnimation, !reducedMotion, !systemReducedMotion else { return }
            while !Task.isCancelled {
                let duration = animation.durations[frame % animation.durations.count]
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                frame = (frame + 1) % animation.durations.count
            }
        }
    }

    private var currentImage: NSImage? {
        if let lookDirection {
            return SpriteSheet.shared.frame(row: lookDirection.row, column: lookDirection.column)
        }
        return SpriteSheet.shared.frame(row: animation.row, column: frame)
    }
}

private struct FramelessActionButton: View {
    let action: RadialAction
    let icon: String
    let label: String
    let isActive: Bool
    let handler: () -> Void

    var body: some View {
        Button(action: handler) {
            ZStack {
                // A nearly transparent fill gives SF Symbols with hollow centers
                // (notably the magnifier) one continuous hit-test surface without
                // adding any visible circle or frame.
                Rectangle()
                    .fill(Color.white.opacity(0.001))

                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 25, weight: .semibold))
                        .frame(height: 29)
                    Text(label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(isActive ? Color.orange : Color.white)
                .shadow(color: .black.opacity(0.92), radius: 3, y: 1)
            }
            .frame(width: 86, height: 68)
            .contentShape(.interaction, Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 86, height: 68)
        .contentShape(.interaction, Rectangle())
        .help(help)
        .accessibilityLabel(help)
    }

    private var help: String {
        switch action {
        case .voice: "Start or stop the OpenAI realtime voice assistant"
        case .search: "Open or close quick Google search"
        case .pomodoro: "Open or close the focus timer"
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
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 13)
        .frame(width: 244, height: 46)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.45), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 5)
        .onAppear { focused = true }
    }
}

private struct VoiceStatusPanel: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: model.voice.status == .speaking ? "waveform" : "mic.fill")
                    .symbolEffect(
                        .variableColor.iterative,
                        isActive: model.voice.status.isConnected && !model.reducedMotion && !systemReducedMotion
                    )
                    .foregroundStyle(.orange)
                Text(model.voice.status.label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text(model.selectedVoice.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if case let .error(message) = model.voice.status {
                HStack(alignment: .top, spacing: 8) {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            } else if let warning = model.voice.lastWarning {
                Text(warning)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else if !model.voice.assistantTranscript.isEmpty {
                Text(model.voice.assistantTranscript)
                    .font(.caption)
                    .lineLimit(2)
            } else {
                Text(model.voice.status == .disconnected
                     ? "Starting live conversation…"
                     : "Live conversation is on · click Voice again to end")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 270)
        .frame(minHeight: 68)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.45), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
        .contentShape(Rectangle())
        .onTapGesture { model.dismissVoiceError() }
        .accessibilityAction(named: "Dismiss voice error") {
            model.dismissVoiceError()
        }
    }
}

private struct PomodoroPanel: View {
    @ObservedObject var model: AppModel

    private let presets = [15, 25, 30, 45]

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Label("Focus", systemImage: "timer")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                Text(stateLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: model.pomodoro.remainingProgress)
                    .stroke(
                        model.pomodoro.state == .completed ? Color.green : Color.orange,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(model.pomodoro.formattedRemaining)
                    .font(.system(size: 24, weight: .medium, design: .rounded).monospacedDigit())
            }
            .frame(width: 86, height: 86)

            HStack(spacing: 5) {
                ForEach(presets, id: \.self) { minutes in
                    Button("\(minutes)") { model.pomodoroMinutes = minutes }
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .buttonStyle(FocusPresetButtonStyle(selected: model.pomodoroMinutes == minutes))
                        .disabled(model.pomodoro.state == .running || model.pomodoro.state == .paused)
                }
            }

            HStack(spacing: 8) {
                Button("Reset", action: model.pomodoro.reset)
                    .buttonStyle(FocusControlButtonStyle(color: .white.opacity(0.12)))
                    .disabled(model.pomodoro.state == .idle)
                Button(model.pomodoro.state == .running ? "Pause" : "Start", action: toggleTimer)
                    .buttonStyle(FocusControlButtonStyle(color: model.pomodoro.state == .running ? .orange : .green))
            }
        }
        .padding(11)
        .frame(width: 202, height: 204)
        .foregroundStyle(.white)
        .background(Color.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.18), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.34), radius: 18, y: 8)
    }

    private var stateLabel: String {
        switch model.pomodoro.state {
        case .idle: "Ready"
        case .running: "Focusing"
        case .paused: "Paused"
        case .completed: "Complete"
        }
    }

    private func toggleTimer() {
        if model.pomodoro.state == .running {
            model.pomodoro.pause()
        } else {
            model.pomodoro.start()
        }
    }
}

private struct FocusPresetButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.black : Color.white.opacity(0.82))
            .frame(width: 33, height: 22)
            .background(selected ? Color.white : Color.white.opacity(configuration.isPressed ? 0.18 : 0.08), in: Capsule())
    }
}

private struct FocusControlButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 76, height: 27)
            .background(color.opacity(configuration.isPressed ? 0.65 : 1), in: Capsule())
    }
}

private struct MusicHoneycombCluster: View {
    @ObservedObject var controller: MusicController
    let onAction: (MusicController.Action) -> Void

    private let bubbles: [MusicBubble] = [
        MusicBubble(action: .previous, icon: "backward.fill", size: 29, x: 15, y: 36, color: .orange),
        MusicBubble(action: .favorite, icon: "heart.fill", size: 27, x: 45, y: 14, color: .pink),
        MusicBubble(action: .next, icon: "forward.fill", size: 31, x: 80, y: 31, color: .blue),
        MusicBubble(action: .shuffle, icon: "shuffle", size: 27, x: 23, y: 70, color: .purple),
        MusicBubble(action: .playPause, icon: "pause.fill", size: 40, x: 57, y: 57, color: .red),
        MusicBubble(action: .lyrics, icon: "quote.bubble.fill", size: 25, x: 91, y: 68, color: .cyan),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                ForEach(bubbles) { bubble in
                    Button { onAction(bubble.action) } label: {
                        Image(systemName: bubble.icon)
                            .font(.system(size: max(9, bubble.size * 0.36), weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: bubble.size, height: bubble.size)
                    }
                    .buttonStyle(GlassMusicButtonStyle(accent: bubble.color))
                    .contentShape(Circle())
                    .position(x: bubble.x, y: bubble.y)
                    .help(bubble.help)
                    .accessibilityLabel(bubble.help)
                }
            }
            .frame(width: 108, height: 88)
            Text(controller.lastMessage ?? "Music")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.9), radius: 3, y: 1)
        }
        .frame(width: 116, height: 105)
    }
}

private struct GlassMusicButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .fill(accent.opacity(configuration.isPressed ? 0.10 : 0.025))
                    }
                    .overlay {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.58), .white.opacity(0.10)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.6
                            )
                    }
            }
            .shadow(color: accent.opacity(configuration.isPressed ? 0.04 : 0.07), radius: 3, y: 1)
            .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
            .scaleEffect(configuration.isPressed ? 0.91 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct MusicBubble: Identifiable {
    let action: MusicController.Action
    let icon: String
    let size: CGFloat
    let x: CGFloat
    let y: CGFloat
    let color: Color

    var id: MusicController.Action.ID { action.id }

    var help: String {
        switch action {
        case .previous: "Previous track"
        case .playPause: "Pause current media"
        case .next: "Next track"
        case .favorite: "Favorite current track"
        case .shuffle: "Toggle shuffle"
        case .lyrics: "Open lyrics"
        }
    }
}
