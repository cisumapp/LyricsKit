import Foundation

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public protocol LyricsProvider: Sendable {
    var sourceName: String { get }

    func lyrics(for signature: TrackSignature) async throws -> LyricsRecord
    func lyrics(id: Int) async throws -> LyricsRecord
    func search(_ query: LyricsSearchQuery) async throws -> [LyricsRecord]
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public extension LyricsProvider {
    var sourceName: String {
        String(describing: Self.self)
    }

    func lyrics(
        trackName: String,
        artistName: String,
        albumName: String,
        durationInSeconds: Int
    ) async throws -> LyricsRecord {
        try await lyrics(
            for: TrackSignature(
                trackName: trackName,
                artistName: artistName,
                albumName: albumName,
                durationInSeconds: durationInSeconds
            )
        )
    }

    func search(
        query: String,
        artistName: String? = nil,
        albumName: String? = nil
    ) async throws -> [LyricsRecord] {
        try await search(
            LyricsSearchQuery(query: query, artistName: artistName, albumName: albumName)
        )
    }

    func search(
        trackName: String,
        artistName: String? = nil,
        albumName: String? = nil
    ) async throws -> [LyricsRecord] {
        try await search(
            LyricsSearchQuery(trackName: trackName, artistName: artistName, albumName: albumName)
        )
    }

    func searchBestMatch(for signature: TrackSignature) async throws -> LyricsRecord? {
        let results = try await search(
            trackName: signature.trackName,
            artistName: signature.artistName,
            albumName: signature.albumName
        )
        return results.bestMatch(for: signature)
    }

    func searchBestMatch(
        trackName: String,
        artistName: String? = nil,
        albumName: String? = nil,
        durationInSeconds: Int
    ) async throws -> LyricsRecord? {
        try await searchBestMatch(
            for: TrackSignature(
                trackName: trackName,
                artistName: artistName ?? "",
                albumName: albumName ?? "",
                durationInSeconds: durationInSeconds
            )
        )
    }

    func searchSynced(_ query: LyricsSearchQuery) async throws -> [LyricsRecord] {
        try await search(query).syncedOnly()
    }

    func searchSynced(
        query: String,
        artistName: String? = nil,
        albumName: String? = nil
    ) async throws -> [LyricsRecord] {
        try await searchSynced(
            LyricsSearchQuery(query: query, artistName: artistName, albumName: albumName)
        )
    }

    func searchSynced(
        trackName: String,
        artistName: String? = nil,
        albumName: String? = nil
    ) async throws -> [LyricsRecord] {
        try await searchSynced(
            LyricsSearchQuery(trackName: trackName, artistName: artistName, albumName: albumName)
        )
    }

    func parsedLyrics(for signature: TrackSignature) async throws -> ParsedLyrics? {
        (try await lyrics(for: signature)).parsedSyncedLyrics
    }

    func parsedLyrics(
        trackName: String,
        artistName: String,
        albumName: String,
        durationInSeconds: Int
    ) async throws -> ParsedLyrics? {
        (try await lyrics(
            trackName: trackName,
            artistName: artistName,
            albumName: albumName,
            durationInSeconds: durationInSeconds
        )).parsedSyncedLyrics
    }

    func parsedLyrics(id: Int) async throws -> ParsedLyrics? {
        (try await lyrics(id: id)).parsedSyncedLyrics
    }

    func parsedBestLyrics(for signature: TrackSignature) async throws -> ParsedLyrics? {
        (try await searchBestMatch(for: signature))?.parsedSyncedLyrics
    }

    func parsedBestLyrics(
        trackName: String,
        artistName: String,
        albumName: String,
        durationInSeconds: Int
    ) async throws -> ParsedLyrics? {
        (try await searchBestMatch(
            trackName: trackName,
            artistName: artistName,
            albumName: albumName,
            durationInSeconds: durationInSeconds
        ))?.parsedSyncedLyrics
    }

    func lyricLines(for signature: TrackSignature) async throws -> [LyricLine]? {
        (try await parsedLyrics(for: signature))?.lines
    }

    func lyricLines(
        trackName: String,
        artistName: String,
        albumName: String,
        durationInSeconds: Int
    ) async throws -> [LyricLine]? {
        (try await parsedLyrics(
            trackName: trackName,
            artistName: artistName,
            albumName: albumName,
            durationInSeconds: durationInSeconds
        ))?.lines
    }
}
