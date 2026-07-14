import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var apiKey = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                voiceSection
                behaviorSection
                aboutSection
            }
            .padding(26)
        }
        .frame(width: 540)
        .frame(minHeight: 570)
        .background(Color(nsColor: .windowBackgroundColor))
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
        SettingsCard(title: "OpenAI Voice Assistant", icon: "waveform.circle.fill") {
            VStack(alignment: .leading, spacing: 13) {
                LabeledContent("Model") {
                    Text(RealtimeVoiceService.model)
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Voice") {
                    Picker("Voice", selection: $model.selectedVoice) {
                        ForEach(AppModel.availableVoices, id: \.self) { voice in
                            Text(voice.capitalized).tag(voice)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

                Divider()

                Text(model.hasAPIKey ? "An API key is stored in macOS Keychain." : "No API key is stored yet.")
                    .font(.caption)
                    .foregroundStyle(model.hasAPIKey ? Color.green : Color.secondary)

                HStack {
                    SecureField("Paste a new OpenAI API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        model.saveAPIKey(apiKey)
                        apiKey = ""
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove", role: .destructive) { model.removeAPIKey() }
                        .disabled(!model.hasAPIKey)
                }

                Text("Use your own project key. Joi stores it only in your local Keychain; it is never included in the app or repository.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("Voice personality")
                    .font(.caption.weight(.semibold))
                TextEditor(text: $model.personaInstructions)
                    .font(.system(size: 12))
                    .frame(height: 104)
                    .padding(5)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))

                if let message = model.settingsMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var behaviorSection: some View {
        SettingsCard(title: "Companion", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 13) {
                Toggle("Keep Joi above other windows", isOn: $model.alwaysOnTop)
                Toggle("Reduce animation", isOn: $model.reducedMotion)
                Toggle("Launch Joi at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: updateLaunchAtLogin
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
                    Text("Version 0.3.0")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Quit Joi") { NSApplication.shared.terminate(nil) }
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
