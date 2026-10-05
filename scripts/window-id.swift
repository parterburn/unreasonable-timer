// Prints the window number of an app's largest on-screen window, for `screencapture -l`.
//   swift scripts/window-id.swift "Unreasonable Timer"
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "Unreasonable Timer"
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

func area(_ window: [String: Any]) -> Double {
    guard let bounds = window[kCGWindowBounds as String] as? [String: Double] else { return 0 }
    return (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
}

let windows = info.filter {
    ($0[kCGWindowOwnerName as String] as? String) == owner && ($0[kCGWindowLayer as String] as? Int) == 0
}
guard let window = windows.max(by: { area($0) < area($1) }), let number = window[kCGWindowNumber as String] as? Int else {
    FileHandle.standardError.write(Data("No on-screen window owned by \(owner)\n".utf8))
    exit(1)
}
print(number)
