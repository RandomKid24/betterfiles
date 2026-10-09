import Foundation

/// Zip and unzip with the system tools (the same ones Finder uses).
public enum Archive {
    /// Zips `urls` (all in one folder) next to themselves: "name.zip" for one item, "Archive.zip" for several.
    public static func compress(_ urls: [URL]) -> OpOutcome {
        guard let first = urls.first else { return OpOutcome(source: URL(fileURLWithPath: "/"), destination: nil, error: FileOpError.invalidName) }
        let folder = first.deletingLastPathComponent()
        let name = urls.count == 1 ? first.lastPathComponent + ".zip" : "Archive.zip"
        let dest = FileOps.unique(name, isFolder: false, in: folder, style: .numbered)
        let ok = run("/usr/bin/zip", ["-r", "-q", "-y", dest.path] + urls.map(\.lastPathComponent), in: folder)
        return OpOutcome(source: first, destination: ok ? dest : nil, error: ok ? nil : FileOpError.toolFailed)
    }

    /// Unzips into a new folder named after the archive.
    public static func extract(_ zip: URL) -> OpOutcome {
        let folder = zip.deletingLastPathComponent()
        let dest = FileOps.unique(zip.deletingPathExtension().lastPathComponent, isFolder: true, in: folder, style: .numbered)
        let ok = run("/usr/bin/ditto", ["-x", "-k", zip.path, dest.path], in: folder)
        return OpOutcome(source: zip, destination: ok ? dest : nil, error: ok ? nil : FileOpError.toolFailed)
    }

    private static func run(_ tool: String, _ args: [String], in dir: URL) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.currentDirectoryURL = dir
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
