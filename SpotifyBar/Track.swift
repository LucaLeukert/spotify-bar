import Foundation

struct Track: Equatable, Sendable {
    let name: String
    let artist: String
    let album: String
    let url: String
    let artworkURL: String
}

enum PlaybackState: String, Sendable {
    case playing
    case paused
    case stopped
    case unavailable
}

enum TitleDisplayStyle: String, CaseIterable, Identifiable {
    case titleAndArtist
    case titleOnly
    case artistAndTitle
    case artistOnly

    var id: Self { self }

    var label: String {
        switch self {
        case .titleAndArtist: "Song · Artist"
        case .titleOnly: "Song only"
        case .artistAndTitle: "Artist · Song"
        case .artistOnly: "Artist only"
        }
    }

    func format(track: Track, cleanup: Bool) -> String {
        let title = cleanup ? SongTitleCleaner.clean(track.name) : track.name
        switch self {
        case .titleAndArtist: return "\(title) · \(track.artist)"
        case .titleOnly: return title
        case .artistAndTitle: return "\(track.artist) · \(title)"
        case .artistOnly: return track.artist
        }
    }
}

enum SongTitleCleaner {
    // Removes common release decorations while preserving meaningful parentheses.
    private static let decorations = [
        #"\s*[\(\[]\s*(?:feat\.?|ft\.?|featuring)\s+[^\)\]]+[\)\]]"#,
        #"\s+(?:feat\.?|ft\.?|featuring)\s+.+$"#,
        #"\s*[-–—]\s*(Remaster(?:ed)?|Live|Radio Edit|Single Version|Album Version|Explicit)\b.*$"#,
        #"\s*[\(\[]\s*(?:\d{4}\s+)?(?:Remaster(?:ed)?|Live|Radio Edit|Single Version|Album Version|Explicit)[^\)\]]*[\)\]]\s*$"#
    ]

    static func clean(_ title: String) -> String {
        var result = title
        for pattern in decorations {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
