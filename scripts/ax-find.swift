// Finds an element in an app's windows by accessibility role or subrole and prints the centre
// of the nth match (in the order the accessibility tree lists them, from 1) as "x y" (global,
// top-left origin, like CGWindowList bounds), for scripts/ci-screenshots.sh to click; or with
// `value`, prints its value.
//   swiftc scripts/ax-find.swift -o ax-find
//   ./ax-find "Unreasonable Timer" AXSearchField
//   ./ax-find "Unreasonable Timer" AXTextField 2 value
import AppKit
import ApplicationServices

let args = CommandLine.arguments
guard args.count >= 3, args.count <= 5 else {
    FileHandle.standardError.write(Data("usage: ax-find <app name> <AX role or subrole> [n] [value]\n".utf8))
    exit(2)
}
let wanted = args[2]
let index = args.count >= 4 ? Int(args[3]) ?? 1 : 1
let printValue = args.count == 5 && args[4] == "value"

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

guard matches.indices.contains(index - 1) else {
    fail("ax-find: \(matches.count) \(wanted) in \(args[1]), asked for number \(index)")
}
let element = matches[index - 1]

if printValue {
    print(value(element, kAXValueAttribute) as? String ?? "")
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
