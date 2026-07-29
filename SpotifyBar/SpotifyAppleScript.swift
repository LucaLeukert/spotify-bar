import AppKit
import Foundation

actor SpotifyAppleScript {
    enum Command: Sendable, Hashable {
        case playPause
        case next
        case previous
    }

    struct Snapshot: Sendable {
        let state: PlaybackState
        let track: Track?
    }

    private var snapshotScript: NSAppleScript?
    private var commandScripts: [Command: NSAppleScript] = [:]

    func snapshot() -> Snapshot {
        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.spotify.client"
        ).isEmpty == false else {
            return Snapshot(state: .unavailable, track: nil)
        }

        let source = """
        tell application id "com.spotify.client"
            set playerStatus to (player state as text)
            if playerStatus is "stopped" then return playerStatus
            set currentSong to current track
            set fieldSeparator to ASCII character 30
            return playerStatus & fieldSeparator & (name of currentSong) & fieldSeparator & (artist of currentSong) & fieldSeparator & (album of currentSong) & fieldSeparator & (spotify url of currentSong) & fieldSeparator & (artwork url of currentSong)
        end tell
        """

        guard let value = executeSnapshot(source: source) else {
            return Snapshot(state: .unavailable, track: nil)
        }

        let fields = value.components(separatedBy: String(UnicodeScalar(30)))
        let state = PlaybackState(rawValue: fields.first?.lowercased() ?? "") ?? .stopped
        guard fields.count >= 6 else {
            return Snapshot(state: state, track: nil)
        }

        return Snapshot(
            state: state,
            track: Track(
                name: fields[1],
                artist: fields[2],
                album: fields[3],
                url: fields[4],
                artworkURL: fields[5]
            )
        )
    }

    func send(_ command: Command) {
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        }
        execute(command: command, source: #"tell application id "com.spotify.client" to \#(verb)"#)
    }

    private func executeSnapshot(source: String) -> String? {
        if snapshotScript == nil {
            snapshotScript = compile(source)
        }
        return execute(snapshotScript)?.stringValue
    }

    private func execute(command: Command, source: String) {
        if commandScripts[command] == nil {
            commandScripts[command] = compile(source)
        }
        _ = execute(commandScripts[command])
    }

    private func compile(_ source: String) -> NSAppleScript? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else { return nil }
        return script
    }

    private func execute(_ script: NSAppleScript?) -> NSAppleEventDescriptor? {
        guard let script else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result
    }
}
