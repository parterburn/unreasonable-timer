// Moves the pointer to a point (global, top-left origin, like CGWindowList bounds) and clicks.
// For scripts/ci-screenshots.sh.
//   swiftc scripts/click.swift -o click && ./click 300 650
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count == 3, let x = Double(args[1]), let y = Double(args[2]) else {
    FileHandle.standardError.write(Data("usage: click <x> <y>\n".utf8))
    exit(2)
}
let point = CGPoint(x: x, y: y)

func post(_ type: CGEventType) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
        .post(tap: .cghidEventTap)
}

post(.mouseMoved)
usleep(300_000)
post(.leftMouseDown)
usleep(80_000)
post(.leftMouseUp)
