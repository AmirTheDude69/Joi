import AppKit
import SwiftUI

@MainActor
enum JoiPreviewRenderer {
    static func render(to directory: URL, model: AppModel) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        model.isExpanded = true
        model.activePanel = .none
        try write(
            FloatingCompanionView(model: model).frame(width: 560, height: 520),
            size: CGSize(width: 560, height: 520),
            to: directory.appendingPathComponent("radial-menu.png")
        )

        model.activePanel = .pomodoro
        try write(
            FloatingCompanionView(model: model).frame(width: 560, height: 520),
            size: CGSize(width: 560, height: 520),
            to: directory.appendingPathComponent("focus-timer.png")
        )

        model.activePanel = .voice
        try write(
            FloatingCompanionView(model: model).frame(width: 560, height: 520),
            size: CGSize(width: 560, height: 520),
            to: directory.appendingPathComponent("voice-mode.png")
        )

        try write(
            SettingsView(model: model).frame(width: 540, height: 650),
            size: CGSize(width: 540, height: 650),
            to: directory.appendingPathComponent("settings.png")
        )
    }

    private static func write<Content: View>(_ view: Content, size: CGSize, to url: URL) throws {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw PreviewError.renderFailed
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw PreviewError.renderFailed
        }
        try png.write(to: url, options: .atomic)
    }
}

private enum PreviewError: LocalizedError {
    case renderFailed

    var errorDescription: String? { "The SwiftUI view could not be rendered." }
}
