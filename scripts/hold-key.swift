// Presses or holds a key the way a person does: modifier keys down, one key-down, then
// key-repeat events, then key-up and the modifiers released. For scripts/ci-screenshots.sh, to
// check keyboard handling in the real app.
//   swiftc scripts/hold-key.swift -o hold-key
//   ./hold-key up 10              hold ↑ for ten repeats
//   ./hold-key equals 0 cmd       press ⌘=
//   ./hold-key t 0 ctrl opt cmd   press ⌃⌥⌘T
import CoreGraphics
import Foundation

let codes: [String: CGKeyCode] = [
    "up": 126, "down": 125, "equals": 24, "minus": 27, "zero": 29, "escape": 53, "return": 36,
    "a": 0, "t": 17, "w": 13,
    "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
]
let modifierKeys: [String: (code: CGKeyCode, flag: CGEventFlags)] = [
    "ctrl": (59, .maskControl), "opt": (58, .maskAlternate), "shift": (56, .maskShift), "cmd": (55, .maskCommand),
]
let args = CommandLine.arguments
guard args.count >= 3, let code = codes[args[1]], let repeats = Int(args[2]) else {
    FileHandle.standardError.write(Data("usage: hold-key \(codes.keys.sorted().joined(separator: "|")) <repeats> [ctrl] [opt] [shift] [cmd]\n".utf8))
    exit(2)
}
let modifiers = args.dropFirst(3).compactMap { modifierKeys[$0] }

func post(_ key: CGKeyCode, down: Bool, flags: CGEventFlags, autorepeat: Bool = false) {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)!
    event.flags = flags
    if autorepeat { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
    event.post(tap: .cghidEventTap)
}

// Modifiers go down one at a time, so whatever is watching sees them as a keyboard sends them.
var flags: CGEventFlags = []
for modifier in modifiers {
    flags.insert(modifier.flag)
    post(modifier.code, down: true, flags: flags)
    usleep(40_000)
}

post(code, down: true, flags: flags)
if repeats > 0 { usleep(400_000) }
for _ in 0..<repeats {
    post(code, down: true, flags: flags, autorepeat: true)
    usleep(60_000)
}
usleep(30_000)
post(code, down: false, flags: flags)

for modifier in modifiers.reversed() {
    usleep(40_000)
    flags.remove(modifier.flag)
    post(modifier.code, down: false, flags: flags)
}
