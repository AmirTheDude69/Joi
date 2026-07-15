import AppKit
import Darwin
import SwiftUI
@preconcurrency import UserNotifications

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
final class JoiAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    lazy var model = AppModel()

    private var companionPanel: CompanionPanel?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var dragStartOrigin: NSPoint?
    private var dragStartMouseLocation: NSPoint?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-test") {
            let failures = JoiSelfTest.run()
            fflush(stdout)
            exit(failures == 0 ? 0 : 1)
        }
        if let previewIndex = CommandLine.arguments.firstIndex(of: "--render-previews"),
           CommandLine.arguments.indices.contains(previewIndex + 1) {
            let directory = URL(fileURLWithPath: CommandLine.arguments[previewIndex + 1], isDirectory: true)
            let previewSuiteName = "JoiPreview-\(UUID().uuidString)"
            let previewDefaults = UserDefaults(suiteName: previewSuiteName)!
            let previewModel = AppModel(defaults: previewDefaults)
            defer { previewDefaults.removePersistentDomain(forName: previewSuiteName) }
            do {
                try JoiPreviewRenderer.render(to: directory, model: previewModel)
                print("Rendered Joi previews to \(directory.path)")
                fflush(stdout)
                exit(0)
            } catch {
                fputs("Preview rendering failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        createCompanionPanel()
        createStatusItem()
        wireModel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func createCompanionPanel() {
        let size = CompanionLayout.panelSize(
            expanded: false,
            scale: model.avatarScale,
            radiusScale: model.controlRadiusScale
        )
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
            self?.resizePanel(expanded: expanded, animate: true)
        }
        model.onAvatarScaleChange = { [weak self] _ in
            self?.resizePanel(expanded: self?.model.isExpanded ?? false, animate: false)
        }
        model.onControlRadiusScaleChange = { [weak self] _ in
            self?.resizePanel(expanded: self?.model.isExpanded ?? false, animate: false)
        }
        model.onAlwaysOnTopChange = { [weak self] alwaysOnTop in
            self?.companionPanel?.level = alwaysOnTop ? .floating : .normal
        }
        model.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        model.onQuit = { [weak self] in
            self?.quit()
        }
        model.onWindowDrag = { [weak self] translation in
            self?.dragPanel(translation: translation)
        }
        model.onWindowDragEnded = { [weak self] in
            self?.finishPanelDrag()
        }
    }

    private func resizePanel(expanded: Bool, animate: Bool) {
        guard let panel = companionPanel else { return }
        finishPanelDrag()
        let target = CompanionLayout.panelSize(
            expanded: expanded,
            scale: model.avatarScale,
            radiusScale: model.controlRadiusScale
        )
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
            animate: animate
                && !model.reducedMotion
                && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        panel.orderFrontRegardless()
    }

    private func dragPanel(translation: CGSize) {
        guard let panel = companionPanel else { return }

        let currentMouseLocation = NSEvent.mouseLocation
        if dragStartOrigin == nil || dragStartMouseLocation == nil {
            dragStartOrigin = panel.frame.origin
            // SwiftUI's global coordinates are window-relative and have a
            // downward-positive Y axis. Recover the screen-space mouse-down point
            // from the first translation so the panel does not lag or jump when
            // the drag crosses its recognition threshold.
            dragStartMouseLocation = NSPoint(
                x: currentMouseLocation.x - translation.width,
                y: currentMouseLocation.y + translation.height
            )
        }
        guard let origin = dragStartOrigin, let mouseOrigin = dragStartMouseLocation else { return }

        var frame = panel.frame
        frame.origin = NSPoint(
            x: origin.x + currentMouseLocation.x - mouseOrigin.x,
            y: origin.y + currentMouseLocation.y - mouseOrigin.y
        )
        panel.setFrameOrigin(constrained(frame).origin)
    }

    private func finishPanelDrag() {
        dragStartOrigin = nil
        dragStartMouseLocation = nil
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

    func applicationDidBecomeActive(_ notification: Notification) {
        model.music.refreshAccessibilityPermission()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }
}

final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
