// Holds a key down the way a person does: one key-down, then key-repeat events, then key-up.
// For scripts/ci-screenshots.sh, to check that holding ↑/↓ keeps adjusting the timer.
//   swiftc scripts/hold-key.swift -o hold-key && ./hold-key up 10
import CoreGraphics
import Foundation

let codes: [String: CGKeyCode] = ["up": 126, "down": 125]
let args = CommandLine.arguments
guard args.count == 3, let code = codes[args[1]], let repeats = Int(args[2]) else {
    FileHandle.standardError.write(Data("usage: hold-key up|down <repeats>\n".utf8))
    exit(2)
}

func post(down: Bool, autorepeat: Bool) {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
    if autorepeat { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
    event.post(tap: .cghidEventTap)
}

post(down: true, autorepeat: false)
usleep(400_000)
for _ in 0..<repeats {
    post(down: true, autorepeat: true)
    usleep(60_000)
}
post(down: false, autorepeat: false)
