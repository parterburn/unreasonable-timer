// Finds an element in an app's windows by accessibility role or subrole and prints the centre
// of the nth match (in the order the accessibility tree lists them, from 1), or of the first
// whose label (description, title or identifier) is the given text, as "x y" (global, top-left origin,
// like CGWindowList bounds), for scripts/ci-screenshots.sh to click; or with `value`, prints
// its value; or with `press`, presses it (a menu item, say). `list` prints every match with
// its labels and value, to see what's there.
//   swiftc scripts/ax-find.swift -o ax-find
//   ./ax-find "Unreasonable Timer" AXSearchField
//   ./ax-find "Unreasonable Timer" AXTextField 2 value
//   ./ax-find "Unreasonable Timer" AXTextField "Size of the timer"
//   ./ax-find "Unreasonable Timer" AXTextField list
//   ./ax-find "Unreasonable Timer" AXMenuItem "Copy Link" press
import AppKit
import ApplicationServices

let args = CommandLine.arguments
guard args.count >= 3, args.count <= 5 else {
    FileHandle.standardError.write(Data("usage: ax-find <app name> <AX role or subrole> [n] [value]\n".utf8))
    exit(2)
}
let wanted = args[2]
let selector = args.count >= 4 ? args[3] : "1"
let printValue = args.count == 5 && args[4] == "value"
let press = args.count == 5 && args[4] == "press"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard AXIsProcessTrusted() else { fail("ax-find: not trusted for Accessibility") }
guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == args[1] }) else {
    fail("ax-find: \(args[1]) isn't running")
}

func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
}

var matches: [AXUIElement] = []
func collect(_ element: AXUIElement, depth: Int) {
    let role = value(element, kAXRoleAttribute) as? String
    let subrole = value(element, kAXSubroleAttribute) as? String
    if role == wanted || subrole == wanted { matches.append(element) }
    guard depth < 60, let children = value(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
    for child in children { collect(child, depth: depth + 1) }
}
collect(AXUIElementCreateApplication(app.processIdentifier), depth: 0)

/// The labels an element answers to: its description, title and identifier.
func labels(_ element: AXUIElement) -> [String] {
    [kAXDescriptionAttribute, kAXTitleAttribute, "AXIdentifier"].compactMap {
        (value(element, $0) as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}

if selector == "list" {
    for (number, element) in matches.enumerated() {
        print("\(number + 1)\t\(labels(element).joined(separator: " | "))\t\(value(element, kAXValueAttribute) as? String ?? "")")
    }
    exit(0)
}

let element: AXUIElement
if let index = Int(selector) {
    guard matches.indices.contains(index - 1) else {
        fail("ax-find: \(matches.count) \(wanted) in \(args[1]), asked for number \(index)")
    }
    element = matches[index - 1]
} else {
    guard let match = matches.first(where: { labels($0).contains(selector) }) else {
        fail("ax-find: no \(wanted) labelled \"\(selector)\" in \(args[1])")
    }
    element = match
}

if printValue {
    print(value(element, kAXValueAttribute) as? String ?? "")
    exit(0)
}
if press {
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    guard result == .success else { fail("ax-find: pressing it failed (\(result.rawValue))") }
    exit(0)
}

var origin = CGPoint.zero
var size = CGSize.zero
if let position = value(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID() {
    AXValueGetValue(position as! AXValue, .cgPoint, &origin)
}
if let extent = value(element, kAXSizeAttribute), CFGetTypeID(extent) == AXValueGetTypeID() {
    AXValueGetValue(extent as! AXValue, .cgSize, &size)
}
guard size.width > 0 else { fail("ax-find: \(wanted) has no frame") }
print(Int(origin.x + size.width / 2), Int(origin.y + size.height / 2))
