import AppKit
import SwiftUI

@MainActor
enum JoiPreviewRenderer {
    static func render(to directory: URL, model: AppModel) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let originalScale = model.avatarScale
        let originalRadiusScale = model.controlRadiusScale
        defer {
            model.avatarScale = originalScale
            model.controlRadiusScale = originalRadiusScale
        }
        model.avatarScale = CompanionLayout.defaultAvatarScale
        model.controlRadiusScale = CompanionLayout.defaultControlRadiusScale

        model.isExpanded = true
        model.activePanel = .none
        let expandedSize = CompanionLayout.expandedSize(
            scale: model.avatarScale,
            radiusScale: model.controlRadiusScale
        )
        try write(
            FloatingCompanionView(model: model).frame(width: expandedSize.width, height: expandedSize.height),
            size: expandedSize,
            to: directory.appendingPathComponent("radial-menu.png")
        )

        model.activePanel = .pomodoro
        ["Finish the outline", "Reply to Sam", "Book the table", "Send the files"].forEach {
            _ = model.addFocusTask($0)
        }
        if let completed = model.focusTasks.dropFirst().first {
            model.toggleFocusTask(id: completed.id)
        }
        try write(
            FloatingCompanionView(model: model).frame(width: expandedSize.width, height: expandedSize.height),
            size: expandedSize,
            to: directory.appendingPathComponent("focus-timer.png")
        )

        model.avatarScale = 1.40
        model.controlRadiusScale = CompanionLayout.controlRadiusScaleRange.upperBound
        let largeExpandedSize = CompanionLayout.expandedSize(
            scale: model.avatarScale,
            radiusScale: model.controlRadiusScale
        )
        try write(
            FloatingCompanionView(model: model).frame(
                width: largeExpandedSize.width,
                height: largeExpandedSize.height
            ),
            size: largeExpandedSize,
            to: directory.appendingPathComponent("focus-timer-large.png")
        )

        model.avatarScale = CompanionLayout.defaultAvatarScale
        model.controlRadiusScale = CompanionLayout.defaultControlRadiusScale

        try write(
            SettingsView(model: model).frame(width: 540, height: 880),
            size: CGSize(width: 540, height: 880),
            to: directory.appendingPathComponent("settings.png")
        )

        model.isExpanded = false
        for (name, scale) in [("avatar-small.png", 0.70), ("avatar-large.png", 1.40)] {
            model.avatarScale = scale
            let size = CompanionLayout.collapsedSize(scale: scale)
            try write(
                FloatingCompanionView(model: model).frame(width: size.width, height: size.height),
                size: size,
                to: directory.appendingPathComponent(name)
            )
        }
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
