import AppKit
import SwiftUI

/// Bounded pointer input shared by the rendered interaction and regression checks.
struct SurfacePointer: Equatable {
    var x: Double = 0
    var y: Double = 0

    static func normalized(location: CGPoint, size: CGSize) -> SurfacePointer {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite,
              location.x.isFinite, location.y.isFinite else { return SurfacePointer() }
        return SurfacePointer(x: min(1, max(-1, Double(location.x / size.width * 2 - 1))),
                              y: min(1, max(-1, Double(location.y / size.height * 2 - 1))))
    }

    func offset(hovered: Bool, reducedMotion: Bool, active: Bool, editing: Bool) -> CGSize {
        guard hovered, !reducedMotion, active, !editing else { return .zero }
        return CGSize(width: x * 1.4, height: -2.2 + y * 0.7)
    }
}

/// System compositor owns the blur. This view never installs mouse/event monitors.
struct WindowMaterial: NSViewRepresentable {
    var behindWindow = false

    final class MaterialView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> MaterialView {
        let view = MaterialView()
        view.material = behindWindow ? .underWindowBackground : .hudWindow
        view.blendingMode = behindWindow ? .behindWindow : .withinWindow
        view.state = .followsWindowActiveState
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: MaterialView, context: Context) {
        view.material = behindWindow ? .underWindowBackground : .hudWindow
        view.blendingMode = behindWindow ? .behindWindow : .withinWindow
    }
}

struct WindowBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            if !reduceTransparency && contrast != .increased {
                WindowMaterial(behindWindow: true)
            }
            Color(red: 78/255, green: 80/255, blue: 83/255)
                .opacity(reduceTransparency || contrast == .increased ? 1 : 0.52)
        }
        .allowsHitTesting(false)
    }
}

private final class SurfaceState: ObservableObject {
    @Published var pointer = SurfacePointer()
    @Published var lightPointer = SurfacePointer()
    @Published var hovered = false
}

/// Tracks the untransformed card bounds without intercepting clicks on controls.
private struct SurfaceMouseTracker: NSViewRepresentable {
    var frame: CGRect
    var changed: (SurfacePointer?) -> Void

    final class TrackingView: NSView {
        var changed: ((SurfacePointer?) -> Void)?
        var surfaceFrame = CGRect.zero
        private var monitor: Any?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopTracking()
            guard window != nil else { return }
            // A local, pass-through monitor also sees movement over hosted controls.
            // It never observes other applications or consumes the original event.
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseExited, .leftMouseDown, .leftMouseDragged]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                self.track(event)
                return event
            }
        }

        func stopTracking() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func track(_ event: NSEvent) {
            guard let host = window?.contentView else { changed?(nil); return }
            let location = host.convert(event.locationInWindow, from: nil)
            let point = CGPoint(x: location.x, y: host.isFlipped ? location.y : host.bounds.height - location.y)
            let local = CGPoint(x: point.x - surfaceFrame.minX, y: point.y - surfaceFrame.minY)
            changed?(window?.isKeyWindow == true && surfaceFrame.contains(point)
                     ? SurfacePointer.normalized(location: local, size: surfaceFrame.size) : nil)
        }
    }

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.surfaceFrame = frame
        view.changed = changed
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.surfaceFrame = frame
        view.changed = changed
    }
    static func dismantleNSView(_ view: TrackingView, coordinator: ()) {
        view.stopTracking()
        view.changed = nil
    }
}

private struct FloatingSurface: ViewModifier {
    var editing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.colorSchemeContrast) private var contrast
    @StateObject private var state = SurfaceState()
    private var pointer: SurfacePointer { state.pointer }
    private var hovered: Bool { state.hovered }

    private var animated: Bool { !reduceMotion && activeState != .inactive && !editing }
    private var illuminated: Bool { hovered && activeState != .inactive }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 17, style: .continuous)
        content
            .background {
                ZStack {
                    if !reduceTransparency && contrast != .increased {
                        WindowMaterial()
                    }
                    Color(red: 52/255, green: 54/255, blue: 61/255)
                        .opacity(reduceTransparency || contrast == .increased ? 1 : 0.72)
                    if !reduceTransparency && contrast != .increased {
                        RadialGradient(colors: [Color.white.opacity(0.095), Color.white.opacity(0.025), .clear],
                                       center: UnitPoint(x: 0.5 + state.lightPointer.x * 0.5,
                                                         y: 0.5 + state.lightPointer.y * 0.5),
                                       startRadius: 0, endRadius: 190)
                            // Pointer tracking is immediate; only visibility fades.
                            .transaction { $0.animation = nil }
                            .opacity(illuminated ? 1 : 0)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: illuminated)
                    }
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(contrast == .increased ? 0.4 : illuminated ? 0.15 : 0.065), lineWidth: 0.75))
                .allowsHitTesting(false)
            }
            .rotation3DEffect(.degrees(animated && hovered ? -pointer.y * 0.35 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.18)
            .rotation3DEffect(.degrees(animated && hovered ? pointer.x * 0.4 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.18)
            .offset(pointer.offset(hovered: hovered, reducedMotion: reduceMotion,
                                   active: activeState != .inactive, editing: editing))
            .shadow(color: .black.opacity(illuminated ? 0.17 : 0.055), radius: illuminated ? 12 : 3, x: 0, y: illuminated ? 7 : 2)
            .animation(animated ? .interactiveSpring(response: 0.28, dampingFraction: 0.88, blendDuration: 0.08) : nil, value: pointer)
            .animation(animated ? .easeOut(duration: 0.18) : nil, value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: editing)
            .overlay {
                GeometryReader { geometry in
                    SurfaceMouseTracker(frame: geometry.frame(in: .global)) { position in
                        guard activeState != .inactive, let position else {
                            if state.hovered {
                                state.hovered = false
                                state.pointer = SurfacePointer()
                            }
                            return
                        }
                        if state.lightPointer != position { state.lightPointer = position }
                        if !state.hovered { state.hovered = true }
                        if !editing && !reduceMotion && state.pointer != position { state.pointer = position }
                    }
                }
            }
            .onChange(of: activeState) { _, state in
                if state == .inactive { self.state.hovered = false; self.state.pointer = SurfacePointer() }
            }
            .onChange(of: editing) { _, _ in state.pointer = SurfacePointer() }
            .onChange(of: reduceMotion) { _, _ in state.pointer = SurfacePointer() }
            .onDisappear { state.hovered = false; state.pointer = SurfacePointer() }
    }

}

extension View {
    func floatingSurface(editing: Bool = false) -> some View { modifier(FloatingSurface(editing: editing)) }
}
