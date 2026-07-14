import AppKit
import Darwin
import SwiftUI

@main
struct JoiMacApp: App {
    @NSApplicationDelegateAdaptor(JoiAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class JoiAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()

    private var companionPanel: CompanionPanel?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var dragStartOrigin: NSPoint?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-test") {
            let failures = JoiSelfTest.run()
            fflush(stdout)
            exit(failures == 0 ? 0 : 1)
        }
        if let previewIndex = CommandLine.arguments.firstIndex(of: "--render-previews"),
           CommandLine.arguments.indices.contains(previewIndex + 1) {
            let directory = URL(fileURLWithPath: CommandLine.arguments[previewIndex + 1], isDirectory: true)
            do {
                try JoiPreviewRenderer.render(to: directory, model: model)
                print("Rendered Joi previews to \(directory.path)")
                fflush(stdout)
                exit(0)
            } catch {
                fputs("Preview rendering failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        createCompanionPanel()
        createStatusItem()
        wireModel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func createCompanionPanel() {
        let size = NSSize(width: 170, height: 190)
        let panel = CompanionPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = model.alwaysOnTop ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: FloatingCompanionView(model: model))

        if let visible = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 24, y: visible.minY + 54))
        } else {
            panel.center()
        }
        panel.orderFrontRegardless()
        companionPanel = panel
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Joi")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Joi", action: #selector(showCompanion), keyEquivalent: "j")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Joi", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        item.menu = menu
        statusItem = item
    }

    private func wireModel() {
        model.onExpandedChange = { [weak self] expanded in
            self?.resizePanel(expanded: expanded)
        }
        model.onAlwaysOnTopChange = { [weak self] alwaysOnTop in
            self?.companionPanel?.level = alwaysOnTop ? .floating : .normal
        }
        model.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        model.onWindowDrag = { [weak self] translation in
            self?.dragPanel(translation: translation)
        }
        model.onWindowDragEnded = { [weak self] in
            self?.dragStartOrigin = nil
        }
    }

    private func resizePanel(expanded: Bool) {
        guard let panel = companionPanel else { return }
        let target = expanded ? NSSize(width: 560, height: 520) : NSSize(width: 170, height: 190)
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        var frame = NSRect(
            x: center.x - target.width / 2,
            y: center.y - target.height / 2,
            width: target.width,
            height: target.height
        )
        frame = constrained(frame)
        panel.setFrame(
            frame,
            display: true,
            animate: !model.reducedMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        panel.orderFrontRegardless()
    }

    private func dragPanel(translation: CGSize) {
        guard let panel = companionPanel else { return }
        if dragStartOrigin == nil {
            dragStartOrigin = panel.frame.origin
        }
        guard let origin = dragStartOrigin else { return }
        var frame = panel.frame
        frame.origin = NSPoint(
            x: origin.x + translation.width,
            y: origin.y - translation.height
        )
        panel.setFrame(constrained(frame), display: true)
    }

    private func constrained(_ frame: NSRect) -> NSRect {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }
        var result = frame
        result.origin.x = min(max(result.origin.x, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.origin.y, visible.minY), visible.maxY - result.height)
        return result
    }

    @objc private func showCompanion() {
        companionPanel?.orderFrontRegardless()
    }

    @objc private func showSettings() {
        if let settingsWindow {
            NSApplication.shared.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 570),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Joi Settings"
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("JoiSettingsWindow")
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
