import AppKit
import SwiftUI

struct FloatingCompanionView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @State private var searchText = ""
    @State private var gazeDirection: SpriteLookDirection?

    private var panelSize: CGSize {
        CompanionLayout.panelSize(
            expanded: model.isExpanded,
            scale: model.avatarScale,
            radiusScale: model.controlRadiusScale
        )
    }

    private var expandedClearance: CGFloat {
        CompanionLayout.expandedClearance(scale: model.avatarScale)
    }

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
                    model.noteMenuInteraction()
                    gazeDirection = model.avatarMotion.allowsGazeTracking
                        ? SpriteLookDirection.toward(pointer: location, from: center)
                        : nil
                case .ended:
                    gazeDirection = nil
                }
            }
        }
        .frame(
            width: panelSize.width,
            height: panelSize.height
        )
        .animation(effectiveReducedMotion ? nil : .spring(response: 0.34, dampingFraction: 0.78), value: model.isExpanded)
        .animation(effectiveReducedMotion ? nil : .easeInOut(duration: 0.18), value: model.activePanel)
        .onAppear { model.avatarMotion.setSystemReducedMotion(systemReducedMotion) }
        .onChange(of: systemReducedMotion) { _, enabled in
            model.avatarMotion.setSystemReducedMotion(enabled)
        }
    }

    private var avatar: some View {
        let avatarSize = CompanionLayout.avatarSize(scale: model.avatarScale)
        let scale = CGFloat(model.avatarScale)
        return VStack(spacing: -5 * scale) {
            AnimatedSpriteView(
                animation: model.avatarAnimation,
                lookDirection: model.avatarMotion.allowsGazeTracking ? gazeDirection : nil,
                playsAnimation: model.avatarMotion.isAnimating,
                reducedMotion: model.reducedMotion
            )
            .frame(width: avatarSize.width, height: avatarSize.height)
            .contentShape(Rectangle())
            .contextMenu {
                Button(role: .destructive) {
                    model.quitJoi()
                } label: {
                    Label("Close Joi", systemImage: "xmark.circle")
                }
            }
            .onTapGesture { model.toggleExpanded() }
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    // The AppKit window controller anchors this first translation to
                    // the screen-space mouse origin, then follows NSEvent.mouseLocation.
                    // Keeping the SwiftUI gesture as a signal avoids feedback from the
                    // window moving underneath this view.
                    .onChanged {
                        model.noteMenuInteraction()
                        model.onWindowDrag?($0.translation)
                    }
                    .onEnded { _ in model.onWindowDragEnded?() }
            )
            .accessibilityLabel(model.isExpanded ? "Close Joi controls" : "Open Joi controls")
            .accessibilityAddTraits(.isButton)
            .shadow(color: Color.black.opacity(0.24), radius: 10 * scale, y: 6 * scale)

            Capsule()
                .fill(.black.opacity(0.12))
                .frame(width: 68 * scale, height: 12 * scale)
                .blur(radius: 4 * scale)
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
                            reducedMotion: effectiveReducedMotion,
                            onAction: model.performMusic
                        )
                    } else {
                        FramelessActionButton(
                            action: action,
                            icon: icon(for: action),
                            label: label(for: action),
                            isActive: isActive(action),
                            reducedMotion: effectiveReducedMotion,
                            handler: { handle(action) }
                        )
                    }
                }
                .position(position(for: action, center: center))
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func activePanel(center: CGPoint) -> some View {
        switch model.activePanel {
        case .search:
            QuickSearchPanel(
                text: $searchText,
                reducedMotion: effectiveReducedMotion,
                onInteraction: model.noteMenuInteraction
            ) { query in
                    model.searchGoogle(query)
                    searchText = ""
                }
            .position(
                x: center.x + 105 + expandedClearance * 0.5,
                y: center.y - 155 - expandedClearance
            )
        case .pomodoro:
            PomodoroPanel(model: model, reducedMotion: effectiveReducedMotion)
                .position(
                    x: position(for: .pomodoro, center: center).x,
                    y: CompanionLayout.focusPanelCenterY(
                        center: center,
                        scale: model.avatarScale,
                        radiusScale: model.controlRadiusScale
                    )
                )
        case .none:
            EmptyView()
        }
    }

    private func handle(_ action: RadialAction) {
        model.noteMenuInteraction()
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

    private func position(for action: RadialAction, center: CGPoint) -> CGPoint {
        return RadialLayout.point(
            for: action,
            center: center,
            radius: CompanionLayout.radialRadius(
                scale: model.avatarScale,
                radiusScale: model.controlRadiusScale
            )
        )
    }

    private func isActive(_ action: RadialAction) -> Bool {
        switch action {
        case .search:
            model.activePanel == .search
        case .pomodoro:
            model.activePanel == .pomodoro || model.pomodoro.state == .running
        case .voice, .settings, .codex, .music:
            false
        }
    }

    private func shouldShow(_ action: RadialAction) -> Bool {
        switch model.activePanel {
        case .none:
            true
        case .search:
            action == .search
        case .pomodoro:
            action == .pomodoro
        }
    }

    private func icon(for action: RadialAction) -> String {
        switch action {
        case .voice: "waveform.badge.mic"
        case .search: "magnifyingglass"
        case .pomodoro: "timer"
        case .settings: "gearshape.fill"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .music: "music.note"
        }
    }

    private func label(for action: RadialAction) -> String {
        switch action {
        case .voice: "Voice"
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
        return SpriteSheet.shared.frame(animation: animation, column: frame)
    }
}

private struct FramelessActionButton: View {
    let action: RadialAction
    let icon: String
    let label: String
    let isActive: Bool
    let reducedMotion: Bool
    let handler: () -> Void

    var body: some View {
        Button(action: handler) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 23, weight: .semibold))
                    .frame(height: 27)
                Text(label)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? Color.orange : Color.white)
            .shadow(color: .black.opacity(0.72), radius: 2, y: 1)
            .frame(width: 70, height: 70)
        }
        .buttonStyle(
            GlassFloatingButtonStyle(
                accent: isActive ? .orange : accent,
                shape: .circle,
                reducedMotion: reducedMotion
            )
        )
        .frame(width: 70, height: 70)
        .contentShape(.interaction, Circle())
        .magneticHover(enabled: !reducedMotion)
        .help(help)
        .accessibilityLabel(help)
    }

    private var accent: Color {
        switch action {
        case .voice: .orange
        case .search: .blue
        case .pomodoro: .orange
        case .settings: .white
        case .codex: .cyan
        case .music: .pink
        }
    }

    private var help: String {
        switch action {
        case .voice: "Open ChatGPT Voice in your default browser"
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
    let reducedMotion: Bool
    let onInteraction: () -> Void
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
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(
                GlassFloatingButtonStyle(
                    accent: .orange,
                    shape: .circle,
                    reducedMotion: reducedMotion
                )
            )
            .contentShape(.interaction, Circle())
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .magneticHover(enabled: !reducedMotion)
            .help("Search Google")
            .accessibilityLabel("Search Google")
        }
        .padding(.horizontal, 13)
        .frame(width: 244, height: 46)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.45), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 5)
        .onAppear { focused = true }
        .onChange(of: text) { _, _ in onInteraction() }
    }
}

private struct PomodoroPanel: View {
    @ObservedObject var model: AppModel
    let reducedMotion: Bool
    @State private var newTaskTitle = ""
    @FocusState private var taskFieldFocused: Bool

    private let presets = [15, 25, 30, 45]

    var body: some View {
        VStack(spacing: 6) {
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
                    Button("\(minutes)") {
                        model.noteMenuInteraction()
                        model.pomodoroMinutes = minutes
                    }
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(
                            model.pomodoroMinutes == minutes ? Color.orange : Color.white
                        )
                        .frame(width: 33, height: 22)
                        .buttonStyle(
                            GlassFloatingButtonStyle(
                                accent: model.pomodoroMinutes == minutes ? .orange : .white,
                                shape: .capsule,
                                reducedMotion: reducedMotion
                            )
                        )
                        .disabled(model.pomodoro.state == .running || model.pomodoro.state == .paused)
                        .magneticHover(enabled: !reducedMotion)
                }
            }

            HStack(spacing: 8) {
                Button("Reset") {
                    model.noteMenuInteraction()
                    model.pomodoro.reset()
                }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 27)
                    .buttonStyle(
                        GlassFloatingButtonStyle(
                            accent: .white,
                            shape: .capsule,
                            reducedMotion: reducedMotion
                        )
                    )
                    .disabled(model.pomodoro.state == .idle)
                    .magneticHover(enabled: !reducedMotion)
                Button(model.pomodoro.state == .running ? "Pause" : "Start", action: toggleTimer)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 27)
                    .buttonStyle(
                        GlassFloatingButtonStyle(
                            accent: model.pomodoro.state == .running ? .orange : .green,
                            shape: .capsule,
                            reducedMotion: reducedMotion
                        )
                    )
                    .magneticHover(enabled: !reducedMotion)
            }

            Divider()
                .overlay(.white.opacity(0.16))

            HStack(spacing: 6) {
                TextField(
                    model.activeFocusTasks.count >= model.focusTaskLimit ? "10 active tasks max" : "Add task",
                    text: $newTaskTitle
                )
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .focused($taskFieldFocused)
                .onSubmit(addTask)
                .onChange(of: newTaskTitle) { _, _ in model.noteMenuInteraction() }
                .disabled(model.activeFocusTasks.count >= model.focusTaskLimit)

                Button(action: addTask) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(
                    GlassFloatingButtonStyle(
                        accent: .orange,
                        shape: .circle,
                        reducedMotion: reducedMotion
                    )
                )
                .contentShape(.interaction, Circle())
                .disabled(
                    newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.activeFocusTasks.count >= model.focusTaskLimit
                )
                .magneticHover(enabled: !reducedMotion)
                .help("Add focus task")
                .accessibilityLabel("Add focus task")
            }
            .padding(.leading, 9)
            .padding(.trailing, 4)
            .frame(height: 28)
            .background(.white.opacity(0.08), in: Capsule())

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(model.activeFocusTasks) { task in
                        FocusTaskRow(
                            task: task,
                            reducedMotion: reducedMotion,
                            canToggle: true,
                            onToggle: { model.toggleFocusTask(id: task.id) },
                            onDelete: { model.removeFocusTask(id: task.id) }
                        )
                    }

                    if !model.archivedFocusTasks.isEmpty {
                        HStack(spacing: 5) {
                            Text("Archive")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.54))
                            Rectangle()
                                .fill(.white.opacity(0.12))
                                .frame(height: 0.5)
                        }
                        .padding(.top, model.activeFocusTasks.isEmpty ? 0 : 3)

                        ForEach(model.archivedFocusTasks) { task in
                            FocusTaskRow(
                                task: task,
                                reducedMotion: reducedMotion,
                                canToggle: model.activeFocusTasks.count < model.focusTaskLimit,
                                onToggle: { model.toggleFocusTask(id: task.id) },
                                onDelete: { model.removeFocusTask(id: task.id) }
                            )
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: 133)
        }
        .padding(11)
        .frame(
            width: CompanionLayout.focusPanelSize.width,
            height: CompanionLayout.focusPanelSize.height
        )
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
        model.noteMenuInteraction()
        if model.pomodoro.state == .running {
            model.pomodoro.pause()
        } else {
            model.pomodoro.start()
        }
    }

    private func addTask() {
        if model.addFocusTask(newTaskTitle) {
            newTaskTitle = ""
            taskFieldFocused = true
        }
    }
}

private struct FocusTaskRow: View {
    let task: FocusTaskItem
    let reducedMotion: Bool
    let canToggle: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark" : "circle")
                    .font(.system(size: task.isCompleted ? 9 : 11, weight: .bold))
                    .foregroundStyle(task.isCompleted ? Color.white : Color.white.opacity(0.72))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(
                GlassFloatingButtonStyle(
                    accent: task.isCompleted ? .green : .white,
                    shape: .circle,
                    reducedMotion: reducedMotion
                )
            )
            .contentShape(.interaction, Circle())
            .disabled(!canToggle)
            .magneticHover(enabled: !reducedMotion)
            .help(toggleHelp)
            .accessibilityLabel(
                task.isCompleted
                    ? "Mark \(task.title) incomplete"
                    : "Mark \(task.title) complete"
            )

            Text(task.title)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(task.isCompleted ? Color.white.opacity(0.46) : Color.white.opacity(0.88))
                .strikethrough(task.isCompleted)
                .lineLimit(1)

            Spacer(minLength: 2)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.74))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(
                GlassFloatingButtonStyle(
                    accent: .red,
                    shape: .circle,
                    reducedMotion: reducedMotion
                )
            )
            .contentShape(.interaction, Circle())
            .magneticHover(enabled: !reducedMotion)
            .help("Delete \(task.title)")
            .accessibilityLabel("Delete \(task.title)")
        }
        .frame(height: 24)
    }

    private var toggleHelp: String {
        if task.isCompleted, !canToggle {
            return "10 active tasks max"
        }
        return task.isCompleted ? "Restore task" : "Move task to Archive"
    }
}

private struct MusicHoneycombCluster: View {
    @ObservedObject var controller: MusicController
    let reducedMotion: Bool
    let onAction: (MusicController.Action) -> Void

    private let bubbles: [MusicBubble] = [
        MusicBubble(action: .previous, icon: "backward.fill", size: 29, x: 15, y: 36, color: .orange),
        MusicBubble(action: .favorite, icon: "heart.fill", size: 27, x: 45, y: 14, color: .pink),
        MusicBubble(action: .next, icon: "forward.fill", size: 31, x: 80, y: 31, color: .blue),
        MusicBubble(action: .shuffle, icon: "shuffle", size: 27, x: 23, y: 70, color: .purple),
        MusicBubble(action: .playPause, icon: "play.fill", size: 40, x: 57, y: 57, color: .red),
        MusicBubble(action: .lyrics, icon: "quote.bubble.fill", size: 25, x: 91, y: 68, color: .cyan),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(bubbles) { bubble in
                Button { onAction(bubble.action) } label: {
                    Image(systemName: icon(for: bubble))
                        .font(.system(size: max(9, bubble.size * 0.36), weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: bubble.size, height: bubble.size)
                }
                .buttonStyle(
                    GlassFloatingButtonStyle(
                        accent: bubble.color,
                        shape: .circle,
                        reducedMotion: reducedMotion
                    )
                )
                .contentShape(.interaction, Circle())
                .position(x: bubble.x, y: bubble.y)
                .magneticHover(enabled: !reducedMotion)
                .help(help(for: bubble))
                .accessibilityLabel(help(for: bubble))
            }

            if controller.permissionRequired {
                Button {
                    controller.requestAccessibilityPermission()
                } label: {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(
                    GlassFloatingButtonStyle(
                        accent: .orange,
                        shape: .circle,
                        reducedMotion: reducedMotion
                    )
                )
                .position(x: 106, y: 10)
                .magneticHover(enabled: !reducedMotion)
                .help("Allow Joi to send fallback media keys")
                .accessibilityLabel("Allow Joi to send fallback media keys")
            }
        }
        .frame(width: 118, height: 96)
        .onAppear { controller.refreshAccessibilityPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshAccessibilityPermission()
        }
    }

    private func icon(for bubble: MusicBubble) -> String {
        guard bubble.action == .playPause else { return bubble.icon }
        return controller.isPlaying ? "pause.fill" : "play.fill"
    }

    private func help(for bubble: MusicBubble) -> String {
        guard bubble.action == .playPause else { return bubble.help }
        return controller.isPlaying ? "Pause current media" : "Play current media"
    }
}

private enum GlassFloatingShape {
    case circle
    case capsule
}

private struct GlassFloatingButtonStyle: ButtonStyle {
    let accent: Color
    let shape: GlassFloatingShape
    let reducedMotion: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                surface(isPressed: configuration.isPressed)
            }
            .shadow(color: accent.opacity(configuration.isPressed ? 0.04 : 0.07), radius: 3, y: 1)
            .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed ? 0.91 : 1)
            .animation(reducedMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }

    @ViewBuilder
    private func surface(isPressed: Bool) -> some View {
        switch shape {
        case .circle:
            GlassFloatingSurface(
                shape: Circle(),
                accent: accent,
                isPressed: isPressed
            )
        case .capsule:
            GlassFloatingSurface(
                shape: Capsule(),
                accent: accent,
                isPressed: isPressed
            )
        }
    }
}

private struct GlassFloatingSurface<S: InsettableShape>: View {
    let shape: S
    let accent: Color
    let isPressed: Bool

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape.fill(accent.opacity(isPressed ? 0.12 : 0.035))
            }
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.58), .white.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
            }
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
        case .playPause: "Play or pause current media"
        case .next: "Next track"
        case .favorite: "Favorite current track"
        case .shuffle: "Toggle shuffle"
        case .lyrics: "Open lyrics"
        }
    }
}
