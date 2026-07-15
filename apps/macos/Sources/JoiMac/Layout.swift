import CoreGraphics
import Foundation

enum CompanionLayout {
    static let avatarScaleRange: ClosedRange<Double> = 0.70 ... 1.40
    static let avatarScaleStep = 0.05
    static let defaultAvatarScale = 1.0
    static let controlRadiusScaleRange: ClosedRange<Double> = 0.75 ... 1.25
    static let controlRadiusScaleStep = 0.05
    static let defaultControlRadiusScale = 1.0

    static let baseAvatarSize = CGSize(width: 138, height: 150)
    static let baseCollapsedSize = CGSize(width: 170, height: 190)
    static let baseExpandedSize = CGSize(width: 560, height: 560)
    static let baseRadialRadius: CGFloat = 190
    static let focusPanelSize = CGSize(width: 218, height: 382)
    private static let radialButtonSize = CGSize(width: 70, height: 70)
    private static let musicClusterSize = CGSize(width: 118, height: 96)
    private static let quickSearchPanelSize = CGSize(width: 244, height: 46)
    private static let expandedEdgePadding: CGFloat = 6

    static func normalizedScale(_ value: Double) -> Double {
        guard value.isFinite else { return defaultAvatarScale }
        return min(max(value, avatarScaleRange.lowerBound), avatarScaleRange.upperBound)
    }

    static func normalizedControlRadiusScale(_ value: Double) -> Double {
        guard value.isFinite else { return defaultControlRadiusScale }
        return min(
            max(value, controlRadiusScaleRange.lowerBound),
            controlRadiusScaleRange.upperBound
        )
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

    static func expandedSize(
        scale: Double,
        radiusScale: Double
    ) -> CGSize {
        let clearance = expandedClearance(scale: scale)
        let minimumSize = CGSize(
            width: baseExpandedSize.width + clearance * 2,
            height: baseExpandedSize.height + clearance * 2
        )
        let radius = radialRadius(scale: scale, radiusScale: radiusScale)

        // The focus card sits above the 2-o'clock control while the music
        // honeycomb is wider than the standard radial controls. Size the
        // hosting panel for every possible child instead of relying on one
        // fixed square, especially at the radius slider's extremes.
        let pomodoroX = abs(cos(RadialAction.pomodoro.angleDegrees * .pi / 180) * radius)
        let focusHalfWidth = pomodoroX + focusPanelSize.width / 2
        let musicHalfWidth = abs(cos(RadialAction.music.angleDegrees * .pi / 180) * radius)
            + musicClusterSize.width / 2
        let radialHalfWidth = radius + radialButtonSize.width / 2
        let searchHalfWidth = 105 + clearance * 0.5 + quickSearchPanelSize.width / 2

        let radialHalfHeight = radius + radialButtonSize.height / 2
        let focusButtonY = sin(RadialAction.pomodoro.angleDegrees * .pi / 180) * radius
        let focusPanelTop = focusPanelSize.height + 47 - focusButtonY
        let musicHalfHeight = abs(sin(RadialAction.music.angleDegrees * .pi / 180) * radius)
            + musicClusterSize.height / 2
        let searchHalfHeight = 155 + clearance + quickSearchPanelSize.height / 2

        let requiredHalfWidth = max(
            focusHalfWidth,
            musicHalfWidth,
            radialHalfWidth,
            searchHalfWidth
        ) + expandedEdgePadding
        let requiredHalfHeight = max(
            radialHalfHeight,
            focusPanelTop,
            musicHalfHeight,
            searchHalfHeight
        ) + expandedEdgePadding

        return CGSize(
            width: max(minimumSize.width, requiredHalfWidth * 2),
            height: max(minimumSize.height, requiredHalfHeight * 2)
        )
    }

    static func expandedSize(scale: Double) -> CGSize {
        expandedSize(scale: scale, radiusScale: defaultControlRadiusScale)
    }

    static func panelSize(
        expanded: Bool,
        scale: Double,
        radiusScale: Double
    ) -> CGSize {
        expanded
            ? expandedSize(scale: scale, radiusScale: radiusScale)
            : collapsedSize(scale: scale)
    }

    static func panelSize(expanded: Bool, scale: Double) -> CGSize {
        panelSize(
            expanded: expanded,
            scale: scale,
            radiusScale: defaultControlRadiusScale
        )
    }

    static func radialRadius(scale: Double, radiusScale: Double) -> CGFloat {
        baseRadialRadius * CGFloat(normalizedControlRadiusScale(radiusScale))
            + expandedClearance(scale: scale)
    }

    static func radialRadius(scale: Double) -> CGFloat {
        radialRadius(scale: scale, radiusScale: defaultControlRadiusScale)
    }

    static func focusPanelCenterY(
        center: CGPoint,
        scale: Double,
        radiusScale: Double
    ) -> CGFloat {
        let focusButtonCenter = RadialLayout.point(
            for: .pomodoro,
            center: center,
            radius: radialRadius(scale: scale, radiusScale: radiusScale)
        ).y
        let focusButtonHalfHeight: CGFloat = 35
        let gap: CGFloat = 12
        return focusButtonCenter - focusButtonHalfHeight - gap - focusPanelSize.height / 2
    }

    static func focusPanelCenterY(center: CGPoint, scale: Double) -> CGFloat {
        focusPanelCenterY(
            center: center,
            scale: scale,
            radiusScale: defaultControlRadiusScale
        )
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
