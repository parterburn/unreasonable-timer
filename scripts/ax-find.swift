// Prints the centre of the first element in an app's windows whose accessibility role or
// subrole matches, as "x y" (global, top-left origin, like CGWindowList bounds), for
// scripts/ci-screenshots.sh to click.
//   swiftc scripts/ax-find.swift -o ax-find
//   ./ax-find "Unreasonable Timer" AXSearchField
import AppKit
import ApplicationServices

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: ax-find <app name> <AX role or subrole>\n".utf8))
    exit(2)
}
let wanted = args[2]

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

func find(_ element: AXUIElement, depth: Int) -> AXUIElement? {
    let role = value(element, kAXRoleAttribute) as? String
    let subrole = value(element, kAXSubroleAttribute) as? String
    if role == wanted || subrole == wanted { return element }
    guard depth < 60, let children = value(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
    for child in children {
        if let hit = find(child, depth: depth + 1) { return hit }
    }
    return nil
}

guard let element = find(AXUIElementCreateApplication(app.processIdentifier), depth: 0) else {
    fail("ax-find: no \(wanted) in \(args[1])")
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
