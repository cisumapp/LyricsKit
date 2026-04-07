# LyricsKit

A small Swift package for LRCLIB with a DX-first facade for lookups, search, and synced lyrics playback.

## Installation

Add LyricsKit to your project with Swift Package Manager.

```swift
dependencies: [
    .package(url: "https://github.com/cisumapp/LyricsKit.git", from: "1.0.0")
]
```

## Quick Start

### 1. Fetch lyrics the easy way

Use the top-level facade when you want a simple track lookup with minimal setup.

```swift
import LyricsKit

let lyricsKit = LyricsKit.shared

func loadLyrics() async {
    do {
        let record = try await lyricsKit.lyrics(
            trackName: "I Want to Live",
            artistName: "Borislav Slavov",
            albumName: "Baldur's Gate 3 (Original Game Soundtrack)",
            durationInSeconds: 233
        )

        print(record.trackName)
        print(record.plainLyrics ?? "No plain lyrics")
    } catch {
        print("Failed to load lyrics: \(error)")
    }
}
```

### 2. Render synced lyrics in playback UI

If LRCLIB returns synced lyrics, LyricsKit can parse them into time-stamped lines for you.

```swift
import LyricsKit

func loadSyncedLyrics() async {
    do {
        let parsed = try await LyricsKit.shared.parsedLyrics(
            trackName: "I Want to Live",
            artistName: "Borislav Slavov",
            albumName: "Baldur's Gate 3 (Original Game Soundtrack)",
            durationInSeconds: 233
        )

        if let lines = parsed?.lines {
            for line in lines {
                print("\(line.timestamp): \(line.text)")
            }
        }
    } catch {
        print("Failed to load synced lyrics: \(error)")
    }
}
```

### 3. Search and pick the best match

Use search when you want to browse LRCLIB results or resolve the best candidate for a track.

```swift
import LyricsKit

func searchLyrics() async {
    do {
        let results = try await LyricsKit.shared.searchSynced(
            trackName: "Still Alive",
            artistName: "Jonathan Coulton"
        )

        if let best = results.first {
            print("Best synced result: \(best.trackName)")
        }
    } catch {
        print("Search failed: \(error)")
    }
}
```

### 4. Use the higher-level best match API

When you want the most helpful result with the least amount of logic in your app, use the best-match helpers.

```swift
import LyricsKit

func loadBestLyrics() async {
    do {
        let signature = TrackSignature(
            trackName: "I Want to Live",
            artistName: "Borislav Slavov",
            albumName: "Baldur's Gate 3 (Original Game Soundtrack)",
            durationInSeconds: 233
        )

        if let record = try await LyricsKit.shared.bestLyrics(for: signature) {
            print("Resolved: \(record.artistName) - \(record.trackName)")

            if let parsed = record.parsedSyncedLyrics {
                print("Synced lines: \(parsed.lines.count)")
            }
        }
    } catch {
        print("Best-match lookup failed: \(error)")
    }
}
```

## Facade

LyricsKit is designed to make the common path short, while still exposing the lower-level LRCLIB client when you want more control.

```swift
import LyricsKit

let kit = LyricsKit(
    configuration: .init(
        minimumRequestInterval: 0.35,
        timeoutInterval: 30,
        userAgent: "cisum/1.0"
    )
)

let record = try await kit.lyrics(id: 3396226)
let lines = try await kit.lyricLines(
    trackName: record.trackName,
    artistName: record.artistName,
    albumName: record.albumName,
    durationInSeconds: record.duration
)
```

## Useful Types

- `LyricsKit` - the developer-friendly facade
- `LRCLIBClient` - the lower-level LRCLIB transport client
- `TrackSignature` - the track identity used by LRCLIB lookups
- `LyricsRecord` - the decoded LRCLIB response model
- `ParsedLyrics` - synced lyrics parsed into lines with timestamps
- `LyricLine` - a single timestamped lyric line

## Notes

- The package includes a built-in request rate limiter.
- Response caching is intentionally left to your app.
- `LyricsRecord.parsedSyncedLyrics` and `LyricsKit.parsedLyrics(...)` are the quickest path from LRCLIB data to playback UI.
