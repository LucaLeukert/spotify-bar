import AppKit
import Combine
import Foundation

@MainActor
final class PlayerModel: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var state: PlaybackState = .unavailable
    @Published private(set) var artwork: NSImage?

    private let spotify = SpotifyAppleScript()
    private var refreshTimer: Timer?
    private var playbackObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var loadedArtworkURL: String?

    init() {
        observeSpotify()
        updateFallbackRefresh()
        refresh()
    }

    func refresh(after delay: Duration = .zero) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            if delay != .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled, let self else { return }
            let snapshot = await spotify.snapshot()
            guard !Task.isCancelled else { return }

            if state != snapshot.state {
                state = snapshot.state
            }
            if track != snapshot.track {
                track = snapshot.track
            }
            loadArtwork(for: snapshot.track)
            updateFallbackRefresh()
        }
    }

    func playPause() {
        perform(.playPause)
    }

    func next() {
        perform(.next)
    }

    func previous() {
        perform(.previous)
    }

    func openSpotify() {
        if let url = track.flatMap({ URL(string: $0.url) }) {
            NSWorkspace.shared.open(url)
        } else if let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.spotify.client"
        ) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        }
    }

    func copyURL() {
        guard let url = track?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    func copyEmbedCode() {
        guard let track, let id = Self.trackID(from: track.url) else { return }
        let html = #"<iframe style="border-radius:12px" src="https://open.spotify.com/embed/track/\#(id)" width="100%" height="152" frameborder="0" allowfullscreen="" allow="autoplay; clipboard-write; encrypted-media; fullscreen; picture-in-picture" loading="lazy"></iframe>"#
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(html, forType: .string)
    }

    static func trackID(from url: String) -> String? {
        if url.hasPrefix("spotify:track:") {
            return String(url.dropFirst("spotify:track:".count))
        }
        guard let parsed = URL(string: url),
              parsed.host == "open.spotify.com",
              parsed.pathComponents.count >= 3,
              parsed.pathComponents[1] == "track" else { return nil }
        return parsed.pathComponents[2]
    }

    private func perform(_ command: SpotifyAppleScript.Command) {
        Task {
            await spotify.send(command)
            refresh(after: .milliseconds(350))
        }
    }

    private func loadArtwork(for track: Track?) {
        guard let track,
              !track.artworkURL.isEmpty,
              let url = URL(string: track.artworkURL) else {
            artworkTask?.cancel()
            loadedArtworkURL = nil
            artwork = nil
            return
        }

        guard loadedArtworkURL != track.artworkURL else { return }
        loadedArtworkURL = track.artworkURL
        artworkTask?.cancel()
        artwork = nil

        artworkTask = Task { [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled,
                      let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let image = NSImage(data: data) else { return }
                self?.artwork = Self.menuBarThumbnail(from: image)
            } catch is CancellationError {
                return
            } catch {
                // The menu-bar symbol remains as the offline/error fallback.
            }
        }
    }

    private static func menuBarThumbnail(from source: NSImage) -> NSImage {
        let pointSize = NSSize(width: 16, height: 16)
        let pixelSize = NSSize(width: 32, height: 32)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            source.size = pointSize
            return source
        }

        let previousContext = NSGraphicsContext.current
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        let destination = NSRect(origin: .zero, size: pixelSize)
        NSBezierPath(roundedRect: destination, xRadius: 7, yRadius: 7).addClip()
        source.draw(
            in: destination,
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.current = previousContext

        bitmap.size = pointSize
        let result = NSImage(size: pointSize)
        result.addRepresentation(bitmap)
        return result
    }

    private func observeSpotify() {
        playbackObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == "com.spotify.client" else { return }
                Task { @MainActor in
                    self?.updateFallbackRefresh()
                    self?.refresh(after: .milliseconds(200))
                }
            })
        }
    }

    private func updateFallbackRefresh() {
        let spotifyIsRunning = !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.spotify.client"
        ).isEmpty

        guard spotifyIsRunning else {
            refreshTimer?.invalidate()
            refreshTimer = nil
            return
        }
        guard refreshTimer == nil else { return }

        // Spotify's distributed notification is the primary update mechanism.
        // This coalescible timer only recovers from rare missed notifications.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refreshTimer?.tolerance = 30
    }
}
