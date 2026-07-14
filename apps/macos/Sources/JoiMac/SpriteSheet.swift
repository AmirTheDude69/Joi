import AppKit
import Foundation

enum SpriteAnimation: String, CaseIterable {
    case idle
    case waving
    case jumping
    case failed
    case waiting
    case working
    case review

    var row: Int {
        switch self {
        case .idle: 0
        case .waving: 3
        case .jumping: 4
        case .failed: 5
        case .waiting: 6
        case .working: 7
        case .review: 8
        }
    }

    var durations: [TimeInterval] {
        switch self {
        case .idle: [0.28, 0.11, 0.11, 0.14, 0.14, 0.32]
        case .waving: [0.14, 0.14, 0.14, 0.28]
        case .jumping: [0.14, 0.14, 0.14, 0.14, 0.28]
        case .failed: [0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.24]
        case .waiting: [0.15, 0.15, 0.15, 0.15, 0.15, 0.26]
        case .working: [0.12, 0.12, 0.12, 0.12, 0.12, 0.22]
        case .review: [0.15, 0.15, 0.15, 0.15, 0.15, 0.28]
        }
    }
}

@MainActor
final class SpriteSheet {
    static let shared = SpriteSheet()
    static let cellSize = NSSize(width: 192, height: 208)

    private var source: NSImage?
    private var cache: [String: NSImage] = [:]

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
                .appendingPathComponent("../../spritesheet.webp"),
        ].compactMap { $0 }
        source = candidates.lazy.compactMap(NSImage.init(contentsOf:)).first
        return source
    }
}
