import AppKit

/// Draws the active key map over the game and, in edit mode, lets the user
/// place, move, rebind and delete controls.
@MainActor
final class ControlsOverlay: NSView {
    private let keyMapper: KeyMapper
    private weak var frameView: FrameView?

    var showHints = true { didSet { needsDisplay = true } }
    private(set) var editing = false
    var onEditingChanged: ((Bool) -> Void)?

    private var pending: Control.Kind?
    private var pendingKey: UInt16?
    private var selected: UUID?
    private var awaitingKey = false
    private var awaitingLockKey = false
    private let lockKeyButton = NSButton()
    private let overlayToggle = NSButton(checkboxWithTitle: "Show overlay", target: nil, action: nil)
    private let lockOnOpenToggle = NSButton(checkboxWithTitle: "Lock mouse when game opens", target: nil, action: nil)
    private let settingsRow = NSStackView()
    private var dragging = false
    private let palette = NSStackView()
    private let hint = NSTextField(labelWithString: "")

    init(keyMapper: KeyMapper, frameView: FrameView) {
        self.keyMapper = keyMapper
        self.frameView = frameView
        super.init(frame: .zero)
        buildPalette()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { editing ? super.hitTest(point) : nil }
    override var acceptsFirstResponder: Bool { editing }

    func setEditing(_ on: Bool) {
        guard on != editing else { return }
        editing = on
        keyMapper.releaseAll()
        pending = nil
        awaitingKey = false
        selected = nil
        palette.isHidden = !on
        settingsRow.isHidden = !on
        hint.isHidden = !on
        awaitingLockKey = false
        if on { refreshSettingsRow() }
        if on {
            window?.makeFirstResponder(self)
            if keyMapper.package.isEmpty { setHint("Open a game first. Controls are saved per app.") }
            else { setHint("Editing controls for \(keyMapper.package)") }
        } else {
            keyMapper.save()
            if let frameView { window?.makeFirstResponder(frameView) }
        }
        needsDisplay = true
        onEditingChanged?(on)
    }

    // MARK: Palette

    private func buildPalette() {
        func button(_ title: String, _ symbol: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!,
                             target: self, action: action)
            b.bezelStyle = .rounded
            b.imagePosition = .imageLeading
            return b
        }
        palette.orientation = .horizontal
        palette.spacing = 8
        palette.addArrangedSubview(button("Key", "keyboard", #selector(addTap)))
        palette.addArrangedSubview(button("D-pad", "dpad", #selector(addJoystick)))
        palette.addArrangedSubview(button("Aim", "scope", #selector(addAim)))
        palette.addArrangedSubview(button("Fire", "computermouse", #selector(addFire)))
        palette.addArrangedSubview(button("Clear", "trash", #selector(clearAll)))
        let done = button("Done", "checkmark", #selector(finish))
        done.keyEquivalent = "\r"
        palette.addArrangedSubview(done)
        palette.isHidden = true
        palette.translatesAutoresizingMaskIntoConstraints = false
        addSubview(palette)

        // Per-game options: mouse-lock key, overlay visibility, lock on open.
        lockKeyButton.bezelStyle = .rounded
        lockKeyButton.target = self
        lockKeyButton.action = #selector(changeLockKey)
        overlayToggle.target = self
        overlayToggle.action = #selector(toggleOverlay)
        lockOnOpenToggle.target = self
        lockOnOpenToggle.action = #selector(toggleLockOnOpen)
        let release = NSTextField(labelWithString: "Release mouse: ⌃⌥")
        release.textColor = .secondaryLabelColor
        for v in [lockKeyButton, overlayToggle, lockOnOpenToggle, release] as [NSView] { settingsRow.addArrangedSubview(v) }
        settingsRow.orientation = .horizontal
        settingsRow.spacing = 14
        settingsRow.isHidden = true
        settingsRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(settingsRow)

        hint.textColor = .white
        hint.font = .systemFont(ofSize: 12, weight: .medium)
        hint.alignment = .center
        hint.isHidden = true
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint)

        NSLayoutConstraint.activate([
            palette.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            palette.centerXAnchor.constraint(equalTo: centerXAnchor),
            settingsRow.topAnchor.constraint(equalTo: palette.bottomAnchor, constant: 8),
            settingsRow.centerXAnchor.constraint(equalTo: centerXAnchor),
            hint.topAnchor.constraint(equalTo: settingsRow.bottomAnchor, constant: 8),
            hint.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    private func setHint(_ s: String) { hint.stringValue = s }

    private func refreshSettingsRow() {
        lockKeyButton.title = "Mouse lock key: \(keyMapper.map.lockKey.map { KeyName.label($0) } ?? "none")"
        overlayToggle.state = keyMapper.map.showOverlay ? .on : .off
        lockOnOpenToggle.state = keyMapper.map.lockOnOpen ? .on : .off
        lockOnOpenToggle.isEnabled = keyMapper.hasAim
    }

    @objc private func changeLockKey() {
        guard keyMapper.hasAim else {
            setHint("Add an Aim area first: it's where the locked mouse steers the camera.")
            return
        }
        pending = nil
        awaitingKey = false
        awaitingLockKey = true
        setHint("Press the key that locks the mouse in this game.")
    }

    @objc private func toggleOverlay() {
        keyMapper.map.showOverlay = overlayToggle.state == .on
        setHint(keyMapper.map.showOverlay ? "Key hints show over the game." : "Key hints hidden in game. The controls still work.")
        needsDisplay = true
    }

    @objc private func toggleLockOnOpen() {
        keyMapper.map.lockOnOpen = lockOnOpenToggle.state == .on
    }

    @objc private func addTap() { arm(.tap, key: nil, "Click where the key should tap, then press a key.") }
    @objc private func addJoystick() { arm(.joystick, key: nil, "Click the centre of the game's movement stick (W A S D).") }
    @objc private func addAim() {
        if keyMapper.hasAim { setHint("There's already an aim area. Drag it to move it."); return }
        arm(.aim, key: nil, "Click the middle of the camera area. Your lock key (` by default) locks the mouse there; ⌃⌥ releases it.")
    }
    @objc private func addFire() { arm(.tap, key: MouseKey.left, "Click the fire button. Left click taps it while aiming.") }

    @objc private func clearAll() {
        keyMapper.map.controls.removeAll()
        selected = nil
        needsDisplay = true
    }

    @objc private func finish() { setEditing(false) }

    private func arm(_ kind: Control.Kind, key: UInt16?, _ message: String) {
        guard !keyMapper.package.isEmpty else { return }
        pending = kind
        pendingKey = key
        awaitingKey = false
        setHint(message)
    }

    // MARK: Geometry

    private var picture: CGRect { frameView?.contentRect ?? bounds }

    private func viewPoint(_ c: Control) -> CGPoint {
        let r = picture
        return CGPoint(x: r.minX + c.x * r.width, y: r.maxY - c.y * r.height)
    }

    private func normalised(_ p: CGPoint) -> (Double, Double) {
        let r = picture
        let x = (p.x - r.minX) / max(r.width, 1)
        let y = (r.maxY - p.y) / max(r.height, 1)
        return (Double(min(max(x, 0), 1)), Double(min(max(y, 0), 1)))
    }

    private func radius(_ c: Control) -> CGFloat {
        switch c.kind {
        case .tap: return 18
        case .joystick: return CGFloat(c.radius ?? 0.12) * picture.height
        case .aim: return 26
        }
    }

    private func control(at p: CGPoint) -> Int? {
        keyMapper.map.controls.lastIndex { c in
            let v = viewPoint(c)
            return hypot(p.x - v.x, p.y - v.y) <= max(radius(c), 18)
        }
    }

    // MARK: Editing input

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let kind = pending {
            let (x, y) = normalised(p)
            var c: Control
            switch kind {
            case .tap: c = .tap(pendingKey, x: x, y: y)
            case .joystick: c = .joystick(x: x, y: y)
            case .aim: c = .aim(x: x, y: y)
            }
            keyMapper.map.controls.append(c)
            selected = c.id
            awaitingKey = kind == .tap && c.key == nil
            pending = nil
            setHint(awaitingKey ? "Press a key for this tap." : "Drag to move · click then press a key to rebind · right-click to delete")
            refreshSettingsRow()
        } else if let i = control(at: p) {
            selected = keyMapper.map.controls[i].id
            dragging = true
            let kind = keyMapper.map.controls[i].kind
            awaitingKey = kind != .joystick && keyMapper.map.controls[i].key != MouseKey.left
            setHint(awaitingKey ? "Press a key to rebind, Delete to remove." : "Drag to move · right-click to delete")
        } else {
            selected = nil
            awaitingKey = false
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging, let id = selected,
              let i = keyMapper.map.controls.firstIndex(where: { $0.id == id }) else { return }
        let (x, y) = normalised(convert(event.locationInWindow, from: nil))
        keyMapper.map.controls[i].x = x
        keyMapper.map.controls[i].y = y
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) { dragging = false }

    override func rightMouseDown(with event: NSEvent) {
        guard let i = control(at: convert(event.locationInWindow, from: nil)) else { return }
        keyMapper.map.controls.remove(at: i)
        selected = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if awaitingLockKey {
            awaitingLockKey = false
            if event.keyCode != 53, let i = keyMapper.map.controls.firstIndex(where: { $0.kind == .aim }) {
                keyMapper.map.controls[i].key = event.keyCode
                setHint("The mouse locks with \(KeyName.label(event.keyCode)). ⌃⌥ releases it.")
            } else {
                setHint("")
            }
            refreshSettingsRow()
            needsDisplay = true
            return
        }
        if event.keyCode == 53 {  // Esc
            if pending != nil || awaitingKey { pending = nil; awaitingKey = false; setHint("") }
            else { setEditing(false) }
            return
        }
        guard let id = selected, let i = keyMapper.map.controls.firstIndex(where: { $0.id == id }) else { return }
        if event.keyCode == 51 || event.keyCode == 117 {  // Delete / forward delete
            keyMapper.map.controls.remove(at: i)
            selected = nil
        } else if awaitingKey {
            keyMapper.map.controls[i].key = event.keyCode
            awaitingKey = false
            setHint("Bound to \(KeyName.label(event.keyCode)).")
        }
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        if editing {
            NSColor.black.withAlphaComponent(0.35).setFill()
            bounds.fill()
        } else if !showHints || !keyMapper.map.showOverlay {
            return
        }
        let alpha: CGFloat = editing ? 0.9 : 0.4
        for c in keyMapper.map.controls {
            let p = viewPoint(c)
            let r = radius(c)
            let ring = NSBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            NSColor.black.withAlphaComponent(alpha * 0.5).setFill()
            ring.fill()
            (c.id == selected ? NSColor.systemYellow : NSColor.white).withAlphaComponent(alpha).setStroke()
            ring.lineWidth = c.id == selected ? 3 : 1.5
            ring.stroke()

            switch c.kind {
            case .tap:
                label(KeyName.label(c.key), at: p, alpha: alpha)
            case .joystick:
                let k = c.keys ?? []
                let names = k.map { KeyName.label($0) }
                if names.count == 4 {
                    label(names[0], at: CGPoint(x: p.x, y: p.y + r - 12), alpha: alpha)
                    label(names[1], at: CGPoint(x: p.x - r + 12, y: p.y), alpha: alpha)
                    label(names[2], at: CGPoint(x: p.x, y: p.y - r + 12), alpha: alpha)
                    label(names[3], at: CGPoint(x: p.x + r - 12, y: p.y), alpha: alpha)
                }
            case .aim:
                label("\(KeyName.label(c.key)) aim", at: p, alpha: alpha)
                if editing {
                    let reach = CGFloat(c.radius ?? 0.25) * picture.height
                    let area = NSBezierPath(ovalIn: CGRect(x: p.x - reach, y: p.y - reach, width: reach * 2, height: reach * 2))
                    area.setLineDash([6, 4], count: 2, phase: 0)
                    NSColor.white.withAlphaComponent(0.4).setStroke()
                    area.stroke()
                }
            }
        }
    }

    private func label(_ s: String, at p: CGPoint, alpha: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        ]
        let str = s as NSString
        let size = str.size(withAttributes: attrs)
        str.draw(at: CGPoint(x: p.x - size.width / 2, y: p.y - size.height / 2), withAttributes: attrs)
    }
}
