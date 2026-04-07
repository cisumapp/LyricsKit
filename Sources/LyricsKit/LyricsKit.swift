import Foundation

/// LyricsKit is a developer-friendly facade for LRCLIB lookups and playback helpers.
///
/// Use `LyricsKit.shared` for the common path, or create your own instance when you want to
/// customize the transport configuration. The lower-level `LRCLIBClient` remains available for
/// advanced use, while this facade keeps the most common playback flows short and predictable.
public final class LyricsKit: @unchecked Sendable {
	public struct Configuration: Sendable, Hashable {
		public var baseURL: URL
		public var minimumRequestInterval: TimeInterval
		public var timeoutInterval: TimeInterval
		public var userAgent: String?

		public init(
			baseURL: URL = URL(string: "https://lrclib.net/api")!,
			minimumRequestInterval: TimeInterval = 0.35,
			timeoutInterval: TimeInterval = 30,
			userAgent: String? = "LyricsKit/1.0"
		) {
			self.baseURL = baseURL
			self.minimumRequestInterval = minimumRequestInterval
			self.timeoutInterval = timeoutInterval
			self.userAgent = userAgent
		}

		fileprivate var lrclibConfiguration: LRCLIBClient.Configuration {
			LRCLIBClient.Configuration(
				baseURL: baseURL,
				minimumRequestInterval: minimumRequestInterval,
				timeoutInterval: timeoutInterval,
				userAgent: userAgent
			)
		}
	}

	public static let shared = LyricsKit()

	public var configuration: Configuration {
		didSet {
			rebuildClient()
		}
	}

	public private(set) var lrclib: LRCLIBClient

	private let session: URLSession

	public init(configuration: Configuration = .init(), session: URLSession = .shared) {
		self.configuration = configuration
		self.session = session
		self.lrclib = LRCLIBClient(configuration: configuration.lrclibConfiguration, session: session)
	}

	public func lyrics(for signature: TrackSignature) async throws -> LyricsRecord {
		try await lrclib.lyrics(for: signature)
	}

	public func lyrics(
		trackName: String,
		artistName: String,
		albumName: String,
		durationInSeconds: Int
	) async throws -> LyricsRecord {
		try await lrclib.lyrics(
			trackName: trackName,
			artistName: artistName,
			albumName: albumName,
			durationInSeconds: durationInSeconds
		)
	}

	public func lyrics(id: Int) async throws -> LyricsRecord {
		try await lrclib.lyrics(id: id)
	}

	public func bestLyrics(for signature: TrackSignature) async throws -> LyricsRecord? {
		try await lrclib.bestLyrics(for: signature)
	}

	public func bestLyrics(
		trackName: String,
		artistName: String,
		albumName: String,
		durationInSeconds: Int
	) async throws -> LyricsRecord? {
		try await lrclib.bestLyrics(
			trackName: trackName,
			artistName: artistName,
			albumName: albumName,
			durationInSeconds: durationInSeconds
		)
	}

	public func search(_ query: LyricsSearchQuery) async throws -> [LyricsRecord] {
		try await lrclib.search(query)
	}

	public func search(
		query: String,
		artistName: String? = nil,
		albumName: String? = nil
	) async throws -> [LyricsRecord] {
		try await lrclib.search(query: query, artistName: artistName, albumName: albumName)
	}

	public func search(
		trackName: String,
		artistName: String? = nil,
		albumName: String? = nil
	) async throws -> [LyricsRecord] {
		try await lrclib.search(trackName: trackName, artistName: artistName, albumName: albumName)
	}

	public func searchBestMatch(for signature: TrackSignature) async throws -> LyricsRecord? {
		try await lrclib.searchBestMatch(for: signature)
	}

	public func searchBestMatch(
		trackName: String,
		artistName: String? = nil,
		albumName: String? = nil,
		durationInSeconds: Int
	) async throws -> LyricsRecord? {
		try await lrclib.searchBestMatch(
			trackName: trackName,
			artistName: artistName,
			albumName: albumName,
			durationInSeconds: durationInSeconds
		)
	}

	public func searchSynced(_ query: LyricsSearchQuery) async throws -> [LyricsRecord] {
		try await lrclib.searchSynced(query)
	}

	public func searchSynced(
		query: String,
		artistName: String? = nil,
		albumName: String? = nil
	) async throws -> [LyricsRecord] {
		try await lrclib.searchSynced(query: query, artistName: artistName, albumName: albumName)
	}

	public func searchSynced(
		trackName: String,
		artistName: String? = nil,
		albumName: String? = nil
	) async throws -> [LyricsRecord] {
		try await lrclib.searchSynced(trackName: trackName, artistName: artistName, albumName: albumName)
	}

	public func parsedLyrics(for signature: TrackSignature) async throws -> ParsedLyrics? {
		try await lrclib.parsedLyrics(for: signature)
	}

	public func parsedLyrics(
		trackName: String,
		artistName: String,
		albumName: String,
		durationInSeconds: Int
	) async throws -> ParsedLyrics? {
		try await lrclib.parsedLyrics(
			trackName: trackName,
			artistName: artistName,
			albumName: albumName,
			durationInSeconds: durationInSeconds
		)
	}

	public func parsedBestLyrics(for signature: TrackSignature) async throws -> ParsedLyrics? {
		try await lrclib.parsedBestLyrics(for: signature)
	}

	public func parsedBestLyrics(
		trackName: String,
		artistName: String,
		albumName: String,
		durationInSeconds: Int
	) async throws -> ParsedLyrics? {
		try await lrclib.parsedBestLyrics(
			trackName: trackName,
			artistName: artistName,
			albumName: albumName,
			durationInSeconds: durationInSeconds
		)
	}

	public func lyricLines(for signature: TrackSignature) async throws -> [LyricLine]? {
		try await parsedLyrics(for: signature)?.lines
	}

	public func lyricLines(
		trackName: String,
		artistName: String,
		albumName: String,
		durationInSeconds: Int
	) async throws -> [LyricLine]? {
		try await parsedLyrics(
			trackName: trackName,
			artistName: artistName,
			albumName: albumName,
			durationInSeconds: durationInSeconds
		)?.lines
	}

	private func rebuildClient() {
		lrclib = LRCLIBClient(configuration: configuration.lrclibConfiguration, session: session)
	}
}

extension LyricsKit: LyricsProvider {}
