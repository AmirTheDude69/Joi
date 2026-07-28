import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                voiceSection
                musicSection
                behaviorSection
                aboutSection
            }
            .padding(26)
        }
        .frame(width: 540)
        .frame(minHeight: 570)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.music.refreshAccessibilityPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.music.refreshAccessibilityPermission()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            if let image = SpriteSheet.shared.frame(row: 0, column: 0) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 70)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Joi Settings")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Your floating AI companion")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var voiceSection: some View {
        SettingsCard(title: "ChatGPT Voice", icon: "waveform.circle.fill") {
            VStack(alignment: .leading, spacing: 13) {
                Text("Voice now opens the official ChatGPT website in your default browser. No API key is needed in Joi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Recommended voice") {
                    Text("Maple")
                        .fontWeight(.semibold)
                }
                Text("After ChatGPT opens, select its Voice icon once and allow browser microphone access. You can then return to your other apps while the conversation continues if your ChatGPT settings support background conversations.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open ChatGPT") { model.openChatGPTVoiceFromSettings() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .magneticHover(enabled: !model.reducedMotion)
                    Button("Remove old Joi API key…", role: .destructive) {
                        model.removeLegacyAPIKey()
                    }
                    .magneticHover(enabled: !model.reducedMotion)
                }

                if let message = model.settingsMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var musicSection: some View {
        SettingsCard(title: "Music Controls", icon: "play.circle.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(
                        model.music.accessibilityGranted ? "Ready" : "Ready through Now Playing",
                        systemImage: model.music.accessibilityGranted ? "checkmark.circle.fill" : "music.note"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.music.accessibilityGranted ? Color.green : Color.secondary)
                    Spacer()
                    Button {
                        model.music.openAccessibilitySettings()
                    } label: {
                        Image(systemName: "hand.raised.fill")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .magneticHover(enabled: !model.reducedMotion)
                    .help("Open Accessibility Settings")
                    .accessibilityLabel("Open Accessibility Settings")
                    if model.music.automationPermissionRequired {
                        Button {
                            model.music.openAutomationSettings()
                        } label: {
                            Image(systemName: "cursorarrow.click.2")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                        .magneticHover(enabled: !model.reducedMotion)
                        .help("Allow Joi to control Spotify in Arc")
                        .accessibilityLabel("Allow Joi to control Spotify in Arc")
                    }
                }

                Text("Transport controls follow the current macOS Now Playing source. Shuffle and Favorite use the current player's supported commands, with a local Spotify Web control when Arc owns Now Playing.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var behaviorSection: some View {
        SettingsCard(title: "Companion", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("Avatar size", systemImage: "person.crop.circle")
                    Spacer()
                    Text(model.avatarScale, format: .percent.precision(.fractionLength(0)))
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                    Button("Default") { model.avatarScale = CompanionLayout.defaultAvatarScale }
                        .disabled(abs(model.avatarScale - CompanionLayout.defaultAvatarScale) < 0.001)
                        .magneticHover(enabled: !model.reducedMotion)
                }
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: $model.avatarScale,
                        in: CompanionLayout.avatarScaleRange,
                        step: CompanionLayout.avatarScaleStep
                    )
                    .accessibilityLabel("Avatar size")
                    .accessibilityValue(
                        Text(model.avatarScale, format: .percent.precision(.fractionLength(0)))
                    )
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label("Control radius", systemImage: "circle.dotted")
                    Spacer()
                    Text(model.controlRadiusScale, format: .percent.precision(.fractionLength(0)))
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                    Button("Default") {
                        model.controlRadiusScale = CompanionLayout.defaultControlRadiusScale
                    }
                    .disabled(
                        abs(
                            model.controlRadiusScale
                                - CompanionLayout.defaultControlRadiusScale
                        ) < 0.001
                    )
                    .magneticHover(enabled: !model.reducedMotion)
                }
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Closer")
                    Slider(
                        value: $model.controlRadiusScale,
                        in: CompanionLayout.controlRadiusScaleRange,
                        step: CompanionLayout.controlRadiusScaleStep
                    )
                    .accessibilityLabel("Control radius")
                    .accessibilityValue(
                        Text(
                            model.controlRadiusScale,
                            format: .percent.precision(.fractionLength(0))
                        )
                    )
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .help("Farther")
                }

                Divider()

                HStack {
                    Label("Close controls after inactivity", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    Text("\(model.menuAutoCloseSeconds) seconds")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                }
                Slider(
                    value: Binding(
                        get: { Double(model.menuAutoCloseSeconds) },
                        set: { model.menuAutoCloseSeconds = Int($0.rounded()) }
                    ),
                    in: Double(MenuInactivityPolicy.secondsRange.lowerBound)
                        ... Double(MenuInactivityPolicy.secondsRange.upperBound),
                    step: Double(MenuInactivityPolicy.secondsStep)
                )
                .accessibilityLabel("Control menu inactivity timeout")
                .accessibilityValue("\(model.menuAutoCloseSeconds) seconds")

                Divider()

                Toggle("Keep Joi above other windows", isOn: $model.alwaysOnTop)
                Toggle("Reduce animation", isOn: $model.reducedMotion)
                Toggle("Launch Joi at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in updateLaunchAtLogin(enabled) }
                ))
                if let launchMessage {
                    Text(launchMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Pomodoro length")
                    Spacer()
                    Stepper("\(model.pomodoroMinutes) minutes", value: $model.pomodoroMinutes, in: 5 ... 90, step: 5)
                        .frame(width: 180)
                }
            }
        }
    }

    private var aboutSection: some View {
        SettingsCard(title: "About", icon: "info.circle.fill") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Joi is an AI companion inspired by a character. She is not a human and does not impersonate your partner.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Version \(appVersion)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Quit Joi") { NSApplication.shared.terminate(nil) }
                        .magneticHover(enabled: !model.reducedMotion)
                }
            }
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            launchMessage = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchMessage = "Move Joi to Applications before enabling launch at login."
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.orange)
            content
        }
        .padding(17)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.12)))
    }
}
