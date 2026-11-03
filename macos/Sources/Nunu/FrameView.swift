import AppKit
import EmulatorAPI

/// Hosts the Metal layer and translates Mac input into Android multitouch/keys.
@MainActor
final class FrameView: NSView {
    let renderer: FrameRenderer
    let keyMapper: KeyMapper
    var client: EngineClient? {
        didSet { keyMapper.client = client }
    }

    private enum Finger {
        static let mouse: Int32 = 0
        static let scroll: Int32 = 1
        static let pinchA: Int32 = 2
        static let pinchB: Int32 = 3
    }

    private var mouseDown = false
    private var scrollPoint: CGPoint?
    private var pinchCentre: CGPoint?
    private var pinchSpread: CGFloat = 0
    private var heldModifiers: NSEvent.ModifierFlags = []

    init(renderer: FrameRenderer, keyMapper: KeyMapper) {
        self.renderer = renderer
        self.keyMapper = keyMapper
        super.init(frame: .zero)
        layer = renderer.layer      // layer-hosting: set before wantsLayer
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        keyMapper.displaySize = { [weak renderer] in renderer?.frameSize ?? .zero }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { true }

    // MARK: Sizing

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        renderer.layer.contentsScale = scale
        let size = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
        if renderer.layer.drawableSize != size {
            renderer.layer.drawableSize = size
            renderer.redraw()
        }
    }

    /// Where the guest picture sits inside this view, in view points.
    var contentRect: CGRect { aspectFit(renderer.frameSize, in: bounds) }

    /// View point -> guest pixel. AppKit's y axis points up, Android's down.
    func guestPoint(_ p: NSPoint) -> CGPoint? {
        let r = contentRect
        let size = renderer.frameSize
        guard r.width > 0, size.width > 0 else { return nil }
        let x = (p.x - r.minX) / r.width * size.width
        let y = (r.maxY - p.y) / r.height * size.height
        return CGPoint(x: min(max(x, 0), size.width - 1), y: min(max(y, 0), size.height - 1))
    }

    private func guestPoint(_ event: NSEvent) -> CGPoint? {
        guestPoint(convert(event.locationInWindow, from: nil))
    }

    private var pointsToPixels: CGFloat {
        let r = contentRect
        return r.width > 0 ? renderer.frameSize.width / r.width : 1
    }

    private var lastMousePoint = CGPoint.zero

    private func send(_ id: Int32, _ p: CGPoint, down: Bool) {
        if id == Finger.mouse { lastMousePoint = p }
        client?.touch([.at(Int(p.x), Int(p.y), id: id, down: down)])
    }

    // MARK: Mouse -> touch

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if keyMapper.aiming {
            _ = keyMapper.key(MouseKey.left, down: true)
            return
        }
        guard let p = guestPoint(event) else { return }
        mouseDown = true
        send(Finger.mouse, p, down: true)
    }

    override func mouseDragged(with event: NSEvent) {
        if keyMapper.aiming {
            keyMapper.mouseDelta(dx: event.deltaX, dy: event.deltaY, pointsToPixels: pointsToPixels)
            return
        }
        guard mouseDown, let p = guestPoint(event) else { return }
        send(Finger.mouse, p, down: true)
    }

    override func mouseUp(with event: NSEvent) {
        if keyMapper.aiming {
            _ = keyMapper.key(MouseKey.left, down: false)
            return
        }
        guard mouseDown, let p = guestPoint(event) else { return }
        mouseDown = false
        send(Finger.mouse, p, down: false)
    }

    override func rightMouseDown(with event: NSEvent) {
        if keyMapper.aiming { _ = keyMapper.key(MouseKey.right, down: true) }
    }

    override func rightMouseDragged(with event: NSEvent) {
        if keyMapper.aiming {
            keyMapper.mouseDelta(dx: event.deltaX, dy: event.deltaY, pointsToPixels: pointsToPixels)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        if keyMapper.aiming { _ = keyMapper.key(MouseKey.right, down: false) }
    }

    override func mouseMoved(with event: NSEvent) {
        if keyMapper.aiming {
            keyMapper.mouseDelta(dx: event.deltaX, dy: event.deltaY, pointsToPixels: pointsToPixels)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    // MARK: Scroll -> one-finger swipe (no Android mouse pointer appears)

    override func scrollWheel(with event: NSEvent) {
        guard !keyMapper.aiming else { return }
        if event.momentumPhase != [] { return }   // Android flings on its own
        let scale = pointsToPixels * (event.hasPreciseScrollingDeltas ? 1 : 12)
        let dx = event.scrollingDeltaX * scale
        let dy = event.scrollingDeltaY * scale

        if event.phase == [] {
            // Notched mouse wheel: a short discrete swipe per click.
            guard let start = guestPoint(event) else { return }
            let end = CGPoint(x: start.x + dx, y: start.y + dy)
            send(Finger.scroll, start, down: true)
            send(Finger.scroll, CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), down: true)
            send(Finger.scroll, end, down: true)
            send(Finger.scroll, end, down: false)
            return
        }
        if event.phase.contains(.began) {
            scrollPoint = guestPoint(event)
            if let p = scrollPoint { send(Finger.scroll, p, down: true) }
        }
        if event.phase.contains(.changed), var p = scrollPoint {
            p.x += dx
            p.y += dy
            scrollPoint = p
            send(Finger.scroll, p, down: true)
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled), let p = scrollPoint {
            send(Finger.scroll, p, down: false)
            scrollPoint = nil
        }
    }

    // MARK: Pinch -> two fingers

    override func magnify(with event: NSEvent) {
        if event.phase.contains(.began) {
            pinchCentre = guestPoint(event)
            pinchSpread = renderer.frameSize.height * 0.12
        }
        guard let c = pinchCentre else { return }
        pinchSpread = max(10, pinchSpread * (1 + event.magnification))
        let a = CGPoint(x: c.x - pinchSpread, y: c.y)
        let b = CGPoint(x: c.x + pinchSpread, y: c.y)
        let lifting = event.phase.contains(.ended) || event.phase.contains(.cancelled)
        client?.touch([
            .at(Int(a.x), Int(a.y), id: Finger.pinchA, down: !lifting),
            .at(Int(b.x), Int(b.y), id: Finger.pinchB, down: !lifting),
        ])
        if lifting { pinchCentre = nil }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        if event.isARepeat { return }   // Android repeats held keys itself
        if event.modifierFlags.contains(.command) { return }  // unclaimed ⌘ shortcut
        if keyMapper.key(event.keyCode, down: true) { return }
        client?.key(macKeyCode: event.keyCode, down: true)
    }

    override func keyUp(with event: NSEvent) {
        if keyMapper.key(event.keyCode, down: false) { return }
        client?.key(macKeyCode: event.keyCode, down: false)
    }

    override func flagsChanged(with event: NSEvent) {
        // ⌃⌥ is the hard release for a locked mouse, like VMware/Parallels:
        // two modifiers no game binds alone, so it never fires by accident.
        let mods = event.modifierFlags.intersection([.control, .option, .command, .shift])
        if keyMapper.aiming, mods == [.control, .option] {
            keyMapper.setAiming(false)
        }
        // Shift/Ctrl/Option go to Android; Command stays with macOS shortcuts.
        let tracked: [(NSEvent.ModifierFlags, Set<UInt16>)] = [
            (.shift, [56, 60]), (.control, [59, 62]), (.option, [58, 61]),
        ]
        let now = event.modifierFlags.intersection([.shift, .control, .option])
        for (flag, codes) in tracked where codes.contains(event.keyCode) {
            let down = now.contains(flag) && !heldModifiers.contains(flag)
            let up = !now.contains(flag) && heldModifiers.contains(flag)
            if down || up, !keyMapper.key(event.keyCode, down: down) {
                client?.key(macKeyCode: event.keyCode, down: down)
            }
        }
        heldModifiers = now
    }

    /// Lift every finger and key when focus leaves, so nothing stays stuck down.
    func releaseInput() {
        if mouseDown { send(Finger.mouse, lastMousePoint, down: false) }
        mouseDown = false
        if let p = scrollPoint { send(Finger.scroll, p, down: false) }
        scrollPoint = nil
        keyMapper.releaseAll()
    }
}
