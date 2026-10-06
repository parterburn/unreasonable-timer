// Presses or holds a key the way a person does: one key-down, then key-repeat events, then
// key-up. For scripts/ci-screenshots.sh, to check keyboard handling in the real app.
//   swiftc scripts/hold-key.swift -o hold-key
//   ./hold-key up 10          hold ↑ for ten repeats
//   ./hold-key equals 0 cmd   press ⌘=
import CoreGraphics
import Foundation

let codes: [String: CGKeyCode] = ["up": 126, "down": 125, "equals": 24, "minus": 27, "zero": 29, "escape": 53]
let args = CommandLine.arguments
guard args.count >= 3, let code = codes[args[1]], let repeats = Int(args[2]) else {
    FileHandle.standardError.write(Data("usage: hold-key up|down|equals|minus|zero|escape <repeats> [cmd]\n".utf8))
    exit(2)
}
let flags: CGEventFlags = args.dropFirst(3).contains("cmd") ? .maskCommand : []

func post(down: Bool, autorepeat: Bool) {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
    event.flags = flags
    if autorepeat { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
    event.post(tap: .cghidEventTap)
}

post(down: true, autorepeat: false)
if repeats > 0 { usleep(400_000) }
for _ in 0..<repeats {
    post(down: true, autorepeat: true)
    usleep(60_000)
}
usleep(30_000)
post(down: false, autorepeat: false)
