import AppKit
import ServiceManagement
import SwiftUI

@main
struct SpotifyBarApp: App {
    @StateObject private var player = PlayerModel()
    @AppStorage("cleanupSongTitles") private var cleanupSongTitles = true
    @AppStorage("titleDisplayStyle") private var titleDisplayStyle = TitleDisplayStyle.titleAndArtist.rawValue
    @AppStorage("hideWhenIdle") private var hideWhenIdle = false
    @AppStorage("showSpotifyIcon") private var showSpotifyIcon = true

    private var style: TitleDisplayStyle {
        TitleDisplayStyle(rawValue: titleDisplayStyle) ?? .titleAndArtist
    }

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(!(hideWhenIdle && player.state == .unavailable))) {
            SpotifyMenu(
                player: player,
                cleanupSongTitles: $cleanupSongTitles,
                titleDisplayStyle: $titleDisplayStyle,
                hideWhenIdle: $hideWhenIdle,
                showSpotifyIcon: $showSpotifyIcon
            )
        } label: {
            HStack(spacing: 5) {
                if showSpotifyIcon {
                    if let artwork = player.artwork {
                        Image(nsImage: artwork)
                            .renderingMode(.original)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: player.state == .playing ? "waveform" : "music.note")
                    }
                }
                Text(menuBarTitle)
            }
            .accessibilityLabel(accessibilityTitle)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarTitle: String {
        guard let track = player.track else {
            return player.state == .unavailable ? "Spotify" : "Not Playing"
        }
        return style.format(track: track, cleanup: cleanupSongTitles)
    }

    private var accessibilityTitle: String {
        guard let track = player.track else { return "Spotify Bar, not playing" }
        return "Spotify Bar, \(track.name) by \(track.artist)"
    }
}

private struct SpotifyMenu: View {
    @ObservedObject var player: PlayerModel
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @Binding var cleanupSongTitles: Bool
    @Binding var titleDisplayStyle: String
    @Binding var hideWhenIdle: Bool
    @Binding var showSpotifyIcon: Bool

    var body: some View {
        Button(player.state == .playing ? "Pause" : "Play", systemImage: player.state == .playing ? "pause.circle" : "play.circle") {
            player.playPause()
        }
        .disabled(player.state == .unavailable)

        Button("Next", systemImage: "forward.end") {
            player.next()
        }
        .disabled(player.state == .unavailable)

        Button("Previous", systemImage: "backward.end") {
            player.previous()
        }
        .disabled(player.state == .unavailable)

        Divider()

        Button("Copy URL", systemImage: "link") {
            player.copyURL()
        }
        .disabled(player.track == nil)
        .keyboardShortcut("c", modifiers: [.command, .shift])

        Button("Copy Embed Code", systemImage: "chevron.left.forwardslash.chevron.right") {
            player.copyEmbedCode()
        }
        .disabled(player.track == nil)
        .keyboardShortcut("e", modifiers: [.command, .shift])

        Button("Open in Spotify", systemImage: "music.note") {
            player.openSpotify()
        }
        .keyboardShortcut("o")

        Divider()

        Menu("Settings", systemImage: "gearshape") {
            Toggle("Clean Up Song Titles", isOn: $cleanupSongTitles)
            Toggle("Show Cover Artwork", isOn: $showSpotifyIcon)
            Toggle("Hide When Spotify Is Closed", isOn: $hideWhenIdle)
            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )

            Divider()

            Menu("Title Display") {
                Picker("Title Display", selection: $titleDisplayStyle) {
                    ForEach(TitleDisplayStyle.allCases) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }
                .labelsHidden()
            }
        }

        Divider()

        Button("Refresh", systemImage: "arrow.clockwise") {
            player.refresh()
        }

        Button("Quit Spotify Bar", systemImage: "power") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

@MainActor
private final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false

    init() {
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSSound.beep()
        }
        refresh()
    }

    private func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            isEnabled = true
        default:
            isEnabled = false
        }
    }
}
