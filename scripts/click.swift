// Moves the pointer to a point (global, top-left origin, like CGWindowList bounds) and clicks,
// or scrolls there. For scripts/ci-screenshots.sh.
//   swiftc scripts/click.swift -o click
//   ./click 300 650              click
//   ./click right 300 650        right-click
//   ./click scroll 512 400 -40   scroll down 40 lines
import CoreGraphics
import Foundation

var args = Array(CommandLine.arguments.dropFirst())
let scrolling = args.first == "scroll"
let rightClick = args.first == "right"
if scrolling || rightClick { args.removeFirst() }
guard args.count == (scrolling ? 3 : 2), let x = Double(args[0]), let y = Double(args[1]) else {
    FileHandle.standardError.write(Data("usage: click [right] <x> <y> | click scroll <x> <y> <lines>\n".utf8))
    exit(2)
}
let point = CGPoint(x: x, y: y)

func post(_ type: CGEventType) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: rightClick ? .right : .left)!
        .post(tap: .cghidEventTap)
}

post(.mouseMoved)
usleep(300_000)
if scrolling, let lines = Int32(args[2]) {
    // A few events rather than one big one, the way a wheel sends them.
    for _ in 0..<10 {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines / 10, wheel2: 0, wheel3: 0)!
        event.location = point
        event.post(tap: .cghidEventTap)
        usleep(30_000)
    }
} else if rightClick {
    post(.rightMouseDown)
    usleep(80_000)
    post(.rightMouseUp)
} else {
    post(.leftMouseDown)
    usleep(80_000)
    post(.leftMouseUp)
}
