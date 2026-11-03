import AppKit
import EmulatorAPI
import Foundation

/// Pseudo key codes so mouse buttons can be bound like keys (used in aim mode).
enum MouseKey {
    static let left: UInt16 = 0x1001
    static let right: UInt16 = 0x1002
}

/// One on-screen control. Positions are normalised (0...1) to the guest display,
/// so a layout survives resolution changes.
struct Control: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case tap, joystick, aim }

    var id = UUID()
    var kind: Kind
    var x: Double
    var y: Double
    /// tap: the key; aim: the toggle key
    var key: UInt16?
    /// joystick: up, left, down, right
    var keys: [UInt16]?
    /// joystick reach / aim re-centre radius, as a fraction of display height
    var radius: Double?
    /// aim: mouse points to guest pixels multiplier
    var sensitivity: Double?

    static func tap(_ key: UInt16?, x: Double, y: Double) -> Control {
        Control(kind: .tap, x: x, y: y, key: key)
    }

    static func joystick(x: Double, y: Double) -> Control {
        Control(kind: .joystick, x: x, y: y, keys: [13, 0, 1, 2], radius: 0.12)  // W A S D
    }

    static func aim(x: Double, y: Double) -> Control {
        Control(kind: .aim, x: x, y: y, key: 50, radius: 0.25, sensitivity: 1.0)  // ` toggles
    }
}

struct KeyMap: Codable, Equatable {
    var controls: [Control] = []

    static func url(for package: String) -> URL {
        Paths.keymaps.appendingPathComponent("\(package).json")
    }

    static func load(_ package: String) -> KeyMap {
        guard let data = try? Data(contentsOf: url(for: package)),
              let map = try? JSONDecoder().decode(KeyMap.self, from: data) else { return KeyMap() }
        return map
    }

    func save(_ package: String) {
        Paths.ensure(Paths.keymaps)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) { try? data.write(to: Self.url(for: package)) }
    }
}

/// Turns keyboard and mouse into multitouch according to the active KeyMap.
/// Anything it doesn't consume falls through to Android as a real key/touch.
@MainActor
final class KeyMapper {
    var map = KeyMap() { didSet { releaseAll() } }
    private(set) var package = ""
    var client: EngineClient?
    /// Current guest display size in pixels.
    var displaySize: () -> CGSize = { .zero }
    var onAimChanged: ((Bool) -> Void)?
    /// Global multiplier from Settings, on top of each aim control's own sensitivity.
    var sensitivityScale = 1.0

    private(set) var aiming = false
    private var heldTaps: Set<UUID> = []
    private var joyHeld: [UUID: Set<UInt16>] = [:]
    private var aimPoint = CGPoint.zero
    private var aimDown = false

    func load(package: String) {
        guard package != self.package else { return }
        self.package = package
        setAiming(false)
        map = KeyMap.load(package)
    }

    func save() {
        guard !package.isEmpty else { return }
        map.save(package)
    }

    // MARK: Keys

    /// Returns true when the key was consumed by a control.
    func key(_ code: UInt16, down: Bool) -> Bool {
        if aiming, code == 53 { // Esc always releases the mouse
            if down { setAiming(false) }
            return true
        }
        var consumed = false
        for (i, c) in map.controls.enumerated() {
            switch c.kind {
            case .tap where c.key == code && (code < 0x1000 || aiming):
                consumed = true
                if down, !heldTaps.contains(c.id) {
                    heldTaps.insert(c.id)
                    touch(c, at: point(c), id: touchID(i), down: true)
                } else if !down, heldTaps.remove(c.id) != nil {
                    touch(c, at: point(c), id: touchID(i), down: false)
                }
            case .joystick where c.keys?.contains(code) == true:
                consumed = true
                updateJoystick(c, index: i, code: code, down: down)
            case .aim where c.key == code:
                consumed = true
                if down { setAiming(!aiming) }
            default:
                break
            }
        }
        return consumed
    }

    // MARK: Aim (mouse-look)

    var hasAim: Bool { map.controls.contains { $0.kind == .aim } }

    func setAiming(_ on: Bool) {
        guard on != aiming else { return }
        if on, !hasAim { return }
        aiming = on
        if !on, aimDown, let (c, i) = aimControl {
            touch(c, at: aimPoint, id: touchID(i), down: false)
            aimDown = false
        }
        // Mouse-bound taps only exist while aiming; let go of any still held.
        for (i, c) in map.controls.enumerated() where c.kind == .tap && (c.key ?? 0) >= 0x1000 && heldTaps.contains(c.id) {
            heldTaps.remove(c.id)
            touch(c, at: point(c), id: touchID(i), down: false)
        }
        CGAssociateMouseAndMouseCursorPosition(on ? 0 : 1)
        if on { NSCursor.hide() } else { NSCursor.unhide() }
        onAimChanged?(on)
    }

    /// Mouse deltas in points. Drags a finger from the aim centre and snaps it back
    /// before it can run off the camera area, the same trick BlueStacks uses.
    func mouseDelta(dx: CGFloat, dy: CGFloat, pointsToPixels: CGFloat) {
        guard aiming, let (c, i) = aimControl else { return }
        let size = displaySize()
        let centre = point(c)
        let sens = CGFloat((c.sensitivity ?? 1) * sensitivityScale)
        if !aimDown {
            aimPoint = centre
            touch(c, at: aimPoint, id: touchID(i), down: true)
            aimDown = true
        }
        aimPoint.x += dx * pointsToPixels * sens
        aimPoint.y += dy * pointsToPixels * sens
        let reach = CGFloat(c.radius ?? 0.25) * size.height
        let off = hypot(aimPoint.x - centre.x, aimPoint.y - centre.y)
        let outside = aimPoint.x < 1 || aimPoint.y < 1 || aimPoint.x > size.width - 2 || aimPoint.y > size.height - 2
        if off > reach || outside {
            touch(c, at: aimPoint, id: touchID(i), down: false)
            aimPoint = centre
            touch(c, at: aimPoint, id: touchID(i), down: true)
        } else {
            touch(c, at: aimPoint, id: touchID(i), down: true)
        }
    }

    private var aimControl: (Control, Int)? {
        guard let i = map.controls.firstIndex(where: { $0.kind == .aim }) else { return nil }
        return (map.controls[i], i)
    }

    // MARK: Joystick

    private func updateJoystick(_ c: Control, index: Int, code: UInt16, down: Bool) {
        var held = joyHeld[c.id] ?? []
        let wasActive = !held.isEmpty
        if down { held.insert(code) } else { held.remove(code) }
        joyHeld[c.id] = held

        let keys = c.keys ?? []
        func on(_ k: Int) -> CGFloat { keys.count > k && held.contains(keys[k]) ? 1 : 0 }
        var v = CGVector(dx: on(3) - on(1), dy: on(2) - on(0))
        let len = hypot(v.dx, v.dy)
        let centre = point(c)
        let id = touchID(index)

        if len == 0 {
            if wasActive { touch(c, at: centre, id: id, down: false) }
            return
        }
        v.dx /= len; v.dy /= len
        let r = CGFloat(c.radius ?? 0.12) * displaySize().height
        let target = CGPoint(x: centre.x + v.dx * r, y: centre.y + v.dy * r)
        if !wasActive {
            // Put the finger down at the stick's centre first so the game anchors there.
            touch(c, at: centre, id: id, down: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
                guard let self, !(self.joyHeld[c.id] ?? []).isEmpty else { return }
                self.touch(c, at: target, id: id, down: true)
            }
        } else {
            touch(c, at: target, id: id, down: true)
        }
    }

    // MARK: Helpers

    func releaseAll() {
        for (i, c) in map.controls.enumerated() where heldTaps.contains(c.id) || !(joyHeld[c.id] ?? []).isEmpty {
            touch(c, at: point(c), id: touchID(i), down: false)
        }
        heldTaps.removeAll()
        joyHeld.removeAll()
        if aiming { setAiming(false) }
    }

    private func point(_ c: Control) -> CGPoint {
        let s = displaySize()
        return CGPoint(x: c.x * s.width, y: c.y * s.height)
    }

    /// 0–3 are reserved for the real mouse, scroll and pinch fingers.
    private func touchID(_ index: Int) -> Int32 { Int32(10 + index) }

    private func touch(_ c: Control, at p: CGPoint, id: Int32, down: Bool) {
        client?.touch([.at(Int(p.x.rounded()), Int(p.y.rounded()), id: id, down: down)])
    }
}

/// Short labels for macOS virtual key codes.
enum KeyName {
    static func label(_ code: UInt16?) -> String {
        guard let code else { return "?" }
        if let s = table[code] { return s }
        return "#\(code)"
    }

    private static let table: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "Esc", 56: "⇧", 58: "⌥",
        59: "⌃", 60: "⇧", 61: "⌥", 62: "⌃", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
        100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12", 118: "F4", 120: "F2",
        122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
        MouseKey.left: "LMB", MouseKey.right: "RMB",
    ]
}
