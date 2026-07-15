import AppKit
import Foundation

enum SpriteAnimation: String, CaseIterable {
    case idle
    case runningRight
    case runningLeft
    case waving
    case jumping
    case failed
    case waiting
    case working
    case review
    case dancing

    /// Codex v2 owns rows 0...8. Standalone-only animations intentionally live
    /// in separate resources so the canonical pet atlas remains installable.
    static let standardCases: [SpriteAnimation] = [
        .idle, .runningRight, .runningLeft, .waving, .jumping,
        .failed, .waiting, .working, .review,
    ]

    var atlasRow: Int? {
        switch self {
        case .idle: 0
        case .runningRight: 1
        case .runningLeft: 2
        case .waving: 3
        case .jumping: 4
        case .failed: 5
        case .waiting: 6
        case .working: 7
        case .review: 8
        case .dancing: nil
        }
    }

    var durations: [TimeInterval] {
        switch self {
        case .idle: [0.28, 0.11, 0.11, 0.14, 0.14, 0.20, 0.32]
        case .runningRight, .runningLeft: [0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.18]
        case .waving: [0.14, 0.14, 0.14, 0.28]
        case .jumping: [0.14, 0.14, 0.14, 0.14, 0.28]
        case .failed: [0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.24]
        case .waiting: [0.15, 0.15, 0.15, 0.15, 0.15, 0.26]
        case .working: [0.12, 0.12, 0.12, 0.12, 0.12, 0.22]
        case .review: [0.15, 0.15, 0.15, 0.15, 0.15, 0.28]
        case .dancing: [0.14, 0.14, 0.12, 0.14, 0.12, 0.16, 0.16, 0.18]
        }
    }

    var cycleDuration: TimeInterval {
        durations.reduce(0, +)
    }
}

/// Rows 9 and 10 contain one clockwise family of 16 planted-body gaze poses.
struct SpriteLookDirection: Equatable {
    let index: Int

    init(index: Int) {
        self.index = ((index % 16) + 16) % 16
    }

    var row: Int { index < 8 ? 9 : 10 }
    var column: Int { index % 8 }

    static func toward(pointer: CGPoint, from center: CGPoint) -> SpriteLookDirection? {
        let dx = pointer.x - center.x
        let dy = pointer.y - center.y
        guard hypot(dx, dy) > 24 else { return nil }
        var angle = atan2(dx, -dy) // zero is up; positive angles move clockwise on screen
        if angle < 0 { angle += 2 * .pi }
        let index = Int((angle / (2 * .pi) * 16).rounded()) % 16
        return SpriteLookDirection(index: index)
    }
}

@MainActor
final class SpriteSheet {
    static let shared = SpriteSheet()
    static let cellSize = NSSize(width: 192, height: 208)

    private var source: NSImage?
    private var cache: [String: NSImage] = [:]

    func frame(animation: SpriteAnimation, column: Int) -> NSImage? {
        if let row = animation.atlasRow {
            return frame(row: row, column: column)
        }
        guard animation == .dancing else { return nil }
        return standaloneFrame(prefix: "joi-dance", column: column)
    }

    func frame(row: Int, column: Int) -> NSImage? {
        let key = "\(row)-\(column)"
        if let cached = cache[key] {
            return cached
        }
        guard let source = loadSource() else { return nil }

        let sourceRect = NSRect(
            x: CGFloat(column) * Self.cellSize.width,
            y: source.size.height - CGFloat(row + 1) * Self.cellSize.height,
            width: Self.cellSize.width,
            height: Self.cellSize.height
        )
        let targetRect = NSRect(origin: .zero, size: Self.cellSize)
        let result = NSImage(size: Self.cellSize)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: targetRect, from: sourceRect, operation: .copy, fraction: 1)
        result.unlockFocus()
        cache[key] = result
        return result
    }

    private func loadSource() -> NSImage? {
        if let source { return source }
        let candidates = [
            Bundle.main.url(forResource: "spritesheet", withExtension: "webp"),
            Bundle.main.resourceURL?.appendingPathComponent("spritesheet.webp"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("spritesheet.webp"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("../../spritesheet.webp"),
        ].compactMap { $0 }
        source = candidates.lazy.compactMap(NSImage.init(contentsOf:)).first
        return source
    }

    private func standaloneFrame(prefix: String, column: Int) -> NSImage? {
        let key = "standalone-\(prefix)-\(column)"
        if let cached = cache[key] {
            return cached
        }

        let resourceName = String(format: "%@-%02d", prefix, column)
        let filename = "\(resourceName).png"
        let workingDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let candidates = [
            Bundle.main.url(forResource: resourceName, withExtension: "png"),
            Bundle.main.resourceURL?.appendingPathComponent(filename),
            workingDirectory
                .appendingPathComponent("apps/macos/Resources/JoiDance")
                .appendingPathComponent(filename),
            workingDirectory
                .appendingPathComponent("Resources/JoiDance")
                .appendingPathComponent(filename),
        ].compactMap { $0 }

        guard let image = candidates.lazy.compactMap(NSImage.init(contentsOf:)).first else {
            return nil
        }
        cache[key] = image
        return image
    }
}
