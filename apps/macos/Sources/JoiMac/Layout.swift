import CoreGraphics
import Foundation

enum RadialAction: String, CaseIterable, Identifiable {
    case voice
    case search
    case pomodoro
    case settings
    case codex
    case music

    var id: String { rawValue }

    var angleDegrees: Double {
        switch self {
        case .voice: -90
        case .search: -30
        case .pomodoro: 30
        case .settings: 90
        case .codex: 150
        case .music: 210
        }
    }
}

enum RadialLayout {
    static func point(
        for action: RadialAction,
        center: CGPoint,
        radius: CGFloat
    ) -> CGPoint {
        let radians = action.angleDegrees * .pi / 180
        return CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }
}

enum GoogleSearch {
    static func url(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components?.url
    }
}
