import CoreGraphics
import Foundation

enum CompanionLayout {
    static let avatarScaleRange: ClosedRange<Double> = 0.70 ... 1.40
    static let avatarScaleStep = 0.05
    static let defaultAvatarScale = 1.0

    static let baseAvatarSize = CGSize(width: 138, height: 150)
    static let baseCollapsedSize = CGSize(width: 170, height: 190)
    static let baseExpandedSize = CGSize(width: 560, height: 560)
    static let baseRadialRadius: CGFloat = 190
    static let focusPanelSize = CGSize(width: 218, height: 318)

    static func normalizedScale(_ value: Double) -> Double {
        guard value.isFinite else { return defaultAvatarScale }
        return min(max(value, avatarScaleRange.lowerBound), avatarScaleRange.upperBound)
    }

    static func avatarSize(scale: Double) -> CGSize {
        let scale = normalizedScale(scale)
        return CGSize(
            width: baseAvatarSize.width * scale,
            height: baseAvatarSize.height * scale
        )
    }

    static func collapsedSize(scale: Double) -> CGSize {
        let scale = normalizedScale(scale)
        return CGSize(
            width: baseCollapsedSize.width * scale,
            height: baseCollapsedSize.height * scale
        )
    }

    static func expandedClearance(scale: Double) -> CGFloat {
        CGFloat(max(0, normalizedScale(scale) - 1)) * 75
    }

    static func expandedSize(scale: Double) -> CGSize {
        let clearance = expandedClearance(scale: scale)
        return CGSize(
            width: baseExpandedSize.width + clearance * 2,
            height: baseExpandedSize.height + clearance * 2
        )
    }

    static func panelSize(expanded: Bool, scale: Double) -> CGSize {
        expanded ? expandedSize(scale: scale) : collapsedSize(scale: scale)
    }

    static func radialRadius(scale: Double) -> CGFloat {
        baseRadialRadius + expandedClearance(scale: scale)
    }

    static func focusPanelCenterY(center: CGPoint, scale: Double) -> CGFloat {
        let focusButtonCenter = RadialLayout.point(
            for: .pomodoro,
            center: center,
            radius: radialRadius(scale: scale)
        ).y
        let focusButtonHalfHeight: CGFloat = 34
        let gap: CGFloat = 12
        return focusButtonCenter - focusButtonHalfHeight - gap - focusPanelSize.height / 2
    }
}

enum MenuInactivityPolicy {
    static let defaultSeconds = 15
    static let secondsRange: ClosedRange<Int> = 5 ... 60
    static let secondsStep = 5

    static func normalizedSeconds(_ value: Int) -> Int {
        min(max(value, secondsRange.lowerBound), secondsRange.upperBound)
    }

    static func shouldClose(
        lastInteraction: Date,
        now: Date,
        timeoutSeconds: Int
    ) -> Bool {
        now.timeIntervalSince(lastInteraction)
            >= TimeInterval(normalizedSeconds(timeoutSeconds))
    }
}

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
