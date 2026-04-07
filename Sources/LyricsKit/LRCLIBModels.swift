import Foundation

public struct TrackSignature: Codable, Sendable, Hashable {
    public let trackName: String
    public let artistName: String
    public let albumName: String
    public let durationInSeconds: Int

    public init(trackName: String, artistName: String, albumName: String, durationInSeconds: Int) {
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.durationInSeconds = durationInSeconds
    }

    public var isValid: Bool {
        trackName.nonEmpty != nil
            && artistName.nonEmpty != nil
            && albumName.nonEmpty != nil
            && durationInSeconds > 0
    }

    func normalized() -> TrackSignature {
        TrackSignature(
            trackName: trackName.lyricsKitTrimmed,
            artistName: artistName.lyricsKitTrimmed,
            albumName: albumName.lyricsKitTrimmed,
            durationInSeconds: durationInSeconds
        )
    }

    var queryItems: [URLQueryItem] {
        guard isValid else { return [] }

        let normalized = normalized()
        return [
            URLQueryItem(name: "track_name", value: normalized.trackName),
            URLQueryItem(name: "artist_name", value: normalized.artistName),
            URLQueryItem(name: "album_name", value: normalized.albumName),
            URLQueryItem(name: "duration", value: String(normalized.durationInSeconds))
        ]
    }
}

public struct LyricsSearchQuery: Codable, Sendable, Hashable {
    public let query: String?
    public let trackName: String?
    public let artistName: String?
    public let albumName: String?

    public init(query: String? = nil, trackName: String? = nil, artistName: String? = nil, albumName: String? = nil) {
        self.query = query
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
    }

    public var isValid: Bool {
        query?.nonEmpty != nil || trackName?.nonEmpty != nil
    }

    func normalized() -> LyricsSearchQuery {
        LyricsSearchQuery(
            query: query?.nonEmpty,
            trackName: trackName?.nonEmpty,
            artistName: artistName?.nonEmpty,
            albumName: albumName?.nonEmpty
        )
    }

    var queryItems: [URLQueryItem] {
        guard isValid else { return [] }

        let normalized = normalized()
        var items: [URLQueryItem] = []
        if let query = normalized.query {
            items.append(URLQueryItem(name: "q", value: query))
        }
        if let trackName = normalized.trackName {
            items.append(URLQueryItem(name: "track_name", value: trackName))
        }
        if let artistName = normalized.artistName {
            items.append(URLQueryItem(name: "artist_name", value: artistName))
        }
        if let albumName = normalized.albumName {
            items.append(URLQueryItem(name: "album_name", value: albumName))
        }
        return items
    }
}

public struct LyricsRecord: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let trackName: String
    public let artistName: String
    public let albumName: String
    public let duration: Int
    public let instrumental: Bool
    public let plainLyrics: String?
    public let syncedLyrics: String?

    public init(
        id: Int,
        trackName: String,
        artistName: String,
        albumName: String,
        duration: Int,
        instrumental: Bool,
        plainLyrics: String?,
        syncedLyrics: String?
    ) {
        self.id = id
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.duration = duration
        self.instrumental = instrumental
        self.plainLyrics = plainLyrics
        self.syncedLyrics = syncedLyrics
    }

    public var parsedSyncedLyrics: ParsedLyrics? {
        ParsedLyrics(syncedLyrics: syncedLyrics)
    }

    public var hasSyncedLyrics: Bool {
        parsedSyncedLyrics != nil
    }

    public var lyricLines: [LyricLine]? {
        parsedSyncedLyrics?.lines
    }
}

public struct ParsedLyrics: Codable, Sendable, Hashable {
    public let lines: [LyricLine]

    public init(lines: [LyricLine]) {
        self.lines = lines.sorted { lhs, rhs in
            lhs.timestamp < rhs.timestamp
        }
    }

    public init?(syncedLyrics: String?) {
        guard let syncedLyrics else { return nil }

        let parsed = Self.parse(syncedLyrics)
        guard !parsed.isEmpty else { return nil }
        self.lines = parsed
    }

    public var isEmpty: Bool {
        lines.isEmpty
    }

    public func line(at playbackTime: TimeInterval) -> LyricLine? {
        guard playbackTime >= 0 else { return nil }
        return lines.last { $0.timestamp <= playbackTime }
    }

    public func currentLine(at playbackTime: TimeInterval) -> LyricLine? {
        line(at: playbackTime)
    }

    public func nextLine(after playbackTime: TimeInterval) -> LyricLine? {
        guard playbackTime >= 0 else { return lines.first }
        return lines.first { $0.timestamp > playbackTime }
    }

    public func previousLine(before playbackTime: TimeInterval) -> LyricLine? {
        guard playbackTime >= 0 else { return nil }
        return lines.last { $0.timestamp < playbackTime }
    }

    public var timeRange: ClosedRange<TimeInterval>? {
        guard let first = lines.first?.timestamp, let last = lines.last?.timestamp else {
            return nil
        }
        return first...last
    }

    public func progress(at playbackTime: TimeInterval, within duration: TimeInterval? = nil) -> Double? {
        guard playbackTime >= 0 else { return nil }

        let upperBound = duration ?? lines.last?.timestamp
        guard let upperBound, upperBound > 0 else { return nil }

        let clampedPlaybackTime = min(max(playbackTime, 0), upperBound)
        return clampedPlaybackTime / upperBound
    }

    private static func parse(_ syncedLyrics: String) -> [LyricLine] {
        let rawLines = syncedLyrics.components(separatedBy: .newlines)
        var parsed: [(timestamp: TimeInterval, order: Int, text: String)] = []
        var order = 0

        for rawLine in rawLines {
            let matches = timestampRegex.matches(
                in: rawLine,
                range: NSRange(location: 0, length: (rawLine as NSString).length)
            )

            guard !matches.isEmpty else { continue }
            guard let lastMatchRange = Range(matches[matches.count - 1].range, in: rawLine) else { continue }

            let text = String(rawLine[lastMatchRange.upperBound...]).lyricsKitTrimmed

            for match in matches {
                guard let timestamp = timestamp(from: match, in: rawLine) else { continue }
                parsed.append((timestamp: timestamp, order: order, text: text))
                order += 1
            }
        }

        return parsed
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.order < rhs.order
                }
                return lhs.timestamp < rhs.timestamp
            }
            .map { LyricLine(timestamp: $0.timestamp, text: $0.text) }
    }

    private static func timestamp(from match: NSTextCheckingResult, in line: String) -> TimeInterval? {
        guard let minutes = string(in: line, range: match.range(at: 1)),
              let seconds = string(in: line, range: match.range(at: 2)) else {
            return nil
        }

        let minuteValue = Double(minutes) ?? 0
        let secondValue = Double(seconds) ?? 0
        let fractionValue = fractionalSeconds(from: match, in: line)

        return minuteValue * 60 + secondValue + fractionValue
    }

    private static func fractionalSeconds(from match: NSTextCheckingResult, in line: String) -> TimeInterval {
        guard let fraction = string(in: line, range: match.range(at: 3)), !fraction.isEmpty else {
            return 0
        }

        var digits = String(fraction.prefix(3))
        while digits.count < 3 {
            digits.append("0")
        }

        return (Double(digits) ?? 0) / 1000
    }

    private static func string(in line: String, range: NSRange) -> String? {
        guard let range = Range(range, in: line) else { return nil }
        return String(line[range])
    }

    private static let timestampRegex: NSRegularExpression = {
        let pattern = #"\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\]"#
        return try! NSRegularExpression(pattern: pattern)
    }()
}

public struct LyricLine: Codable, Sendable, Hashable {
    public let timestamp: TimeInterval
    public let text: String

    public init(timestamp: TimeInterval, text: String) {
        self.timestamp = timestamp
        self.text = text
    }
}

public typealias TimedLyric = LyricLine

public extension LyricsRecord {
    var timedLyrics: [TimedLyric]? {
        lyricLines
    }
}

public extension ParsedLyrics {
    var timedLyrics: [TimedLyric] {
        lines
    }
}

public extension Array where Element == LyricsRecord {
    func syncedOnly() -> [LyricsRecord] {
        filter(\.hasSyncedLyrics)
    }

    func unsyncedOnly() -> [LyricsRecord] {
        filter { !$0.hasSyncedLyrics }
    }

    func bestMatch(for signature: TrackSignature) -> LyricsRecord? {
        sortedByBestMatch(for: signature).first
    }

    func sortedByBestMatch(for signature: TrackSignature) -> [LyricsRecord] {
        sorted { lhs, rhs in
            lhs.matchScore(for: signature) > rhs.matchScore(for: signature)
        }
    }
}

extension LyricsRecord {
    func matchScore(for signature: TrackSignature) -> Int {
        let expected = signature.normalized()
        var score = 0

        score += Self.textScore(actual: trackName, expected: expected.trackName, exact: 1_000, partial: 500)
        score += Self.textScore(actual: artistName, expected: expected.artistName, exact: 700, partial: 350)
        score += Self.textScore(actual: albumName, expected: expected.albumName, exact: 300, partial: 150)

        let durationDifference = abs(duration - expected.durationInSeconds)
        score += max(0, 600 - (durationDifference * 60))

        if hasSyncedLyrics {
            score += 200
        }

        if plainLyrics != nil {
            score += 40
        }

        return score
    }

    private static func textScore(actual: String, expected: String, exact: Int, partial: Int) -> Int {
        let actualKey = actual.lyricsKitComparisonKey
        let expectedKey = expected.lyricsKitComparisonKey

        guard !actualKey.isEmpty, !expectedKey.isEmpty else {
            return 0
        }

        if actualKey == expectedKey {
            return exact
        }

        if actualKey.contains(expectedKey) || expectedKey.contains(actualKey) {
            return partial
        }

        let actualTokens = Set(actualKey.split(separator: " "))
        let expectedTokens = Set(expectedKey.split(separator: " "))
        let overlap = actualTokens.intersection(expectedTokens).count
        guard overlap > 0 else { return 0 }

        return max(partial / 2, overlap * 25)
    }
}

extension String {
    var lyricsKitTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonEmpty: String? {
        lyricsKitTrimmed.isEmpty ? nil : lyricsKitTrimmed
    }

    var lyricsKitComparisonKey: String {
        let lowered = folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
        let filtered = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(filtered).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
