import AppKit
import SwiftUI

/// A native SwiftUI adapter for Framer University's supplied Magnetic Hover
/// component. The React component itself can only transform DOM elements, so
/// this preserves its exact defaults and pointer math for Joi's native buttons.
///
/// Source: https://framer.university/resources/magnetic-hover-component-for-framer
/// Supplied source SHA-256: 7515a314e5af55ea3fe17209d531f3b48c67108f08e8f2066761f8be40e88c11
struct MagneticHoverConfiguration: Equatable, Sendable {
    var distance: CGFloat
    var hoverArea: CGFloat
    var smoothing: Double
    var damping: Double

    static let framerUniversityDefault = MagneticHoverConfiguration(
        distance: 10,
        hoverArea: 10,
        smoothing: 50,
        damping: 100
    )

    var stiffness: Double {
        MagneticHoverMath.mapRange(
            smoothing,
            fromLow: 0,
            fromHigh: 100,
            toLow: 2_000,
            toHigh: 50
        )
    }
}
enum MagneticHoverMath {
    static func mapRange(
        _ value: Double,
        fromLow: Double,
        fromHigh: Double,
        toLow: Double,
        toHigh: Double
    ) -> Double {
        guard fromLow != fromHigh else { return toLow }
        let percentage = (value - fromLow) / (fromHigh - fromLow)
        return toLow + percentage * (toHigh - toLow)
    }

    static func offset(
        pointer: CGPoint,
        size: CGSize,
        configuration: MagneticHoverConfiguration = .framerUniversityDefault,
        enabled: Bool = true
    ) -> CGSize {
        guard enabled, size.width > 0, size.height > 0 else { return .zero }
        let hoverArea = configuration.hoverArea
        guard pointer.x >= -hoverArea,
              pointer.x <= size.width + hoverArea,
              pointer.y >= -hoverArea,
              pointer.y <= size.height + hoverArea
        else { return .zero }

        let normalizedX = (pointer.x - size.width / 2) / (size.width / 2)
        let normalizedY = (pointer.y - size.height / 2) / (size.height / 2)
        return CGSize(
            width: normalizedX * configuration.distance,
            height: normalizedY * configuration.distance
        )
    }
}

extension View {
    func magneticHover(
        enabled: Bool = true,
        configuration: MagneticHoverConfiguration = .framerUniversityDefault
    ) -> some View {
        modifier(MagneticHoverModifier(enabled: enabled, configuration: configuration))
    }
}

private struct MagneticHoverModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @State private var offset: CGSize = .zero

    let enabled: Bool
    let configuration: MagneticHoverConfiguration

    private var isActive: Bool {
        enabled && !systemReducedMotion
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                MagneticTrackingView(hoverArea: configuration.hoverArea) { pointer, size in
                    let next = pointer.map {
                        MagneticHoverMath.offset(
                            pointer: $0,
                            size: size,
                            configuration: configuration,
                            enabled: isActive
                        )
                    } ?? .zero
                    updateOffset(next)
                }
                .allowsHitTesting(false)
            }
            .offset(x: offset.width, y: offset.height)
            .onChange(of: isActive) { _, active in
                if !active { updateOffset(.zero) }
            }
            .onDisappear { offset = .zero }
    }

    private func updateOffset(_ next: CGSize) {
        guard next != offset else { return }
        if !isActive || configuration.smoothing == 0 {
            offset = next
        } else {
            withAnimation(
                .interpolatingSpring(
                    mass: 1,
                    stiffness: configuration.stiffness,
                    damping: configuration.damping,
                    initialVelocity: 0
                )
            ) {
                offset = next
            }
        }
    }
}

private struct MagneticTrackingView: NSViewRepresentable {
    let hoverArea: CGFloat
    let onPointerChange: @MainActor (CGPoint?, CGSize) -> Void

    func makeNSView(context: Context) -> MagneticTrackingNSView {
        let view = MagneticTrackingNSView()
        view.hoverArea = hoverArea
        view.onPointerChange = onPointerChange
        return view
    }

    func updateNSView(_ nsView: MagneticTrackingNSView, context: Context) {
        nsView.hoverArea = hoverArea
        nsView.onPointerChange = onPointerChange
        nsView.updateTrackingAreas()
    }
}

private final class MagneticTrackingNSView: NSView {
    var hoverArea: CGFloat = 10
    var onPointerChange: (@MainActor (CGPoint?, CGSize) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingRect = bounds.insetBy(dx: -hoverArea, dy: -hoverArea)
        let area = NSTrackingArea(
            rect: trackingRect,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        report(event)
    }

    override func mouseMoved(with event: NSEvent) {
        report(event)
    }

    override func mouseExited(with event: NSEvent) {
        onPointerChange?(nil, bounds.size)
    }

    private func report(_ event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        // AppKit is y-up while the supplied browser component is y-down.
        let pointer = CGPoint(x: local.x, y: bounds.height - local.y)
        onPointerChange?(pointer, bounds.size)
    }
}
