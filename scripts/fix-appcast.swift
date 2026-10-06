// Points each appcast item's download at its own GitHub release, and drops delta updates.
//
// generate_appcast applies one --download-url-prefix to every item, so after a release the older
// versions would point at the newest release, where their DMGs aren't. Deltas are dropped
// because release.sh doesn't upload them (and GitHub renames files with spaces, which delta
// names have); Sparkle would try one, get a 404, then fall back to the full DMG anyway.
//
//   xcrun swift scripts/fix-appcast.swift release/updates/appcast.xml unreasonable/timer
import Foundation
#if canImport(FoundationXML)
import FoundationXML   // Linux
#endif

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: fix-appcast.swift <appcast.xml> <owner/repo>\n".utf8))
    exit(2)
}
let file = URL(fileURLWithPath: args[1])
let repo = args[2]

let document = try XMLDocument(contentsOf: file, options: [.nodePreserveAll])
var fixed = 0
for case let item as XMLElement in try document.nodes(forXPath: "//item") {
    for case let deltas as XMLElement in try item.nodes(forXPath: "*[local-name()='deltas']") {
        deltas.detach()
    }
    let element = try item.nodes(forXPath: "*[local-name()='shortVersionString']").first?.stringValue
    for case let enclosure as XMLElement in try item.nodes(forXPath: "enclosure") {
        let attribute = enclosure.attributes?.first { $0.localName == "shortVersionString" }?.stringValue
        guard let version = (element ?? attribute)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = enclosure.attribute(forName: "url"),
              let name = url.stringValue.flatMap({ URL(string: $0)?.lastPathComponent })
        else { continue }
        url.stringValue = "https://github.com/\(repo)/releases/download/v\(version)/\(name)"
        fixed += 1
    }
}
try document.xmlData(options: [.nodePreserveAll]).write(to: file)
print("fix-appcast: \(fixed) download links point at their own release; deltas removed")
