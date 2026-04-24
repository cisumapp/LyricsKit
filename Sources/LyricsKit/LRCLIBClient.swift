import Foundation

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public actor LRCLIBClient {
    public struct Configuration: Sendable, Hashable {
        public let baseURL: URL
        public let minimumRequestInterval: TimeInterval
        public let timeoutInterval: TimeInterval
        public let userAgent: String?

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
    }

    private let configuration: Configuration
    private let session: URLSession
    private let decoder: JSONDecoder
    private let rateLimiter: RequestRateLimiter

    public init(configuration: Configuration = .init(), session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        self.decoder = JSONDecoder()
        self.rateLimiter = RequestRateLimiter(minimumInterval: configuration.minimumRequestInterval)
    }

    public func lyrics(for signature: TrackSignature) async throws -> LyricsRecord {
        try await request(.trackSignature(signature))
    }

    public func lyrics(
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

    public func lyrics(id: Int) async throws -> LyricsRecord {
        try await request(.trackID(id))
    }

    public func search(_ query: LyricsSearchQuery) async throws -> [LyricsRecord] {
        try await request(.search(query))
    }

    public func searchBestMatch(for signature: TrackSignature) async throws -> LyricsRecord? {
        let results = try await search(
            trackName: signature.trackName,
            artistName: signature.artistName,
            albumName: signature.albumName
        )
        return results.bestMatch(for: signature)
    }

    public func searchBestMatch(
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

    public func searchSynced(_ query: LyricsSearchQuery) async throws -> [LyricsRecord] {
        try await search(query).syncedOnly()
    }

    public func searchSynced(
        query: String,
        artistName: String? = nil,
        albumName: String? = nil
    ) async throws -> [LyricsRecord] {
        try await searchSynced(
            LyricsSearchQuery(query: query, artistName: artistName, albumName: albumName)
        )
    }

    public func searchSynced(
        trackName: String,
        artistName: String? = nil,
        albumName: String? = nil
    ) async throws -> [LyricsRecord] {
        try await searchSynced(
            LyricsSearchQuery(trackName: trackName, artistName: artistName, albumName: albumName)
        )
    }

    public func bestLyrics(for signature: TrackSignature) async throws -> LyricsRecord? {
        do {
            let exact = try await lyrics(for: signature)
            guard !exact.hasSyncedLyrics else {
                return exact
            }

            let searchResults = try await search(
                trackName: signature.trackName,
                artistName: signature.artistName,
                albumName: signature.albumName
            )

            guard let bestSearch = searchResults.bestMatch(for: signature) else {
                return exact
            }

            return bestSearch.matchScore(for: signature) >= exact.matchScore(for: signature) ? bestSearch : exact
        } catch LyricsKitError.notFound {
            return try await searchBestMatch(for: signature)
        }
    }

    public func bestLyrics(
        trackName: String,
        artistName: String,
        albumName: String,
        durationInSeconds: Int
    ) async throws -> LyricsRecord? {
        try await bestLyrics(
            for: TrackSignature(
                trackName: trackName,
                artistName: artistName,
                albumName: albumName,
                durationInSeconds: durationInSeconds
            )
        )
    }

    public func parsedBestLyrics(for signature: TrackSignature) async throws -> ParsedLyrics? {
        try await bestLyrics(for: signature)?.parsedSyncedLyrics
    }

    public func parsedBestLyrics(
        trackName: String,
        artistName: String,
        albumName: String,
        durationInSeconds: Int
    ) async throws -> ParsedLyrics? {
        try await bestLyrics(
            trackName: trackName,
            artistName: artistName,
            albumName: albumName,
            durationInSeconds: durationInSeconds
        )?.parsedSyncedLyrics
    }

    public func search(
        query: String,
        artistName: String? = nil,
        albumName: String? = nil
    ) async throws -> [LyricsRecord] {
        try await search(
            LyricsSearchQuery(query: query, artistName: artistName, albumName: albumName)
        )
    }

    public func search(
        trackName: String,
        artistName: String? = nil,
        albumName: String? = nil
    ) async throws -> [LyricsRecord] {
        try await search(
            LyricsSearchQuery(trackName: trackName, artistName: artistName, albumName: albumName)
        )
    }

    public func parsedLyrics(for signature: TrackSignature) async throws -> ParsedLyrics? {
        let record = try await lyrics(for: signature)
        return record.parsedSyncedLyrics
    }

    public func parsedLyrics(
        trackName: String,
        artistName: String,
        albumName: String,
        durationInSeconds: Int
    ) async throws -> ParsedLyrics? {
        let record = try await lyrics(
            trackName: trackName,
            artistName: artistName,
            albumName: albumName,
            durationInSeconds: durationInSeconds
        )
        return record.parsedSyncedLyrics
    }

    public func parsedLyrics(id: Int) async throws -> ParsedLyrics? {
        let record = try await lyrics(id: id)
        return record.parsedSyncedLyrics
    }

    private func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        try endpoint.validate()
        try Task.checkCancellation()
        try await rateLimiter.waitIfNeeded()
        try Task.checkCancellation()

        let request = try makeRequest(for: endpoint)
        if let url = request.url {
            LyricsDebugLogger.log("Sending request to LRCLIB: \(url.path)")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LyricsKitError.invalidResponse
            }

            LyricsDebugLogger.log("LRCLIB response status: \(httpResponse.statusCode)")

            switch httpResponse.statusCode {
            case 200...299:
                do {
                    let decoded = try decoder.decode(T.self, from: data)
                    LyricsDebugLogger.log("LRCLIB request succeeded (\(data.count) bytes)")
                    return decoded
                } catch let decodingError as DecodingError {
                    LyricsDebugLogger.log("LRCLIB decoding failed: \(decodingError.localizedDescription)")
                    throw LyricsKitError.decodingFailed(message: String(describing: decodingError))
                } catch {
                    LyricsDebugLogger.log("LRCLIB decoding failed: \(error.localizedDescription)")
                    throw LyricsKitError.decodingFailed(message: error.localizedDescription)
                }
            case 404:
                LyricsDebugLogger.log("LRCLIB resource not found")
                throw LyricsKitError.notFound(Self.decodeErrorPayload(from: data, decoder: decoder))
            case 429:
                let retryAfter = Self.retryAfterSeconds(from: httpResponse)
                LyricsDebugLogger.log("LRCLIB rate limited, retry after: \(retryAfter ?? 0)s")
                let payload = Self.decodeErrorPayload(from: data, decoder: decoder)
                await rateLimiter.penalize(retryAfter: retryAfter)
                throw LyricsKitError.rateLimited(retryAfter: retryAfter, payload: payload)
            default:
                LyricsDebugLogger.log("LRCLIB HTTP error: \(httpResponse.statusCode)")
                throw LyricsKitError.httpError(
                    statusCode: httpResponse.statusCode,
                    payload: Self.decodeErrorPayload(from: data, decoder: decoder),
                    retryAfter: Self.retryAfterSeconds(from: httpResponse)
                )
            }
        } catch let error as CancellationError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            LyricsDebugLogger.log("LRCLIB network error: \(error.localizedDescription)")
            throw LyricsKitError.transport(code: error.errorCode, message: error.localizedDescription)
        } catch {
            LyricsDebugLogger.log("LRCLIB generic error: \(error.localizedDescription)")
            throw LyricsKitError.transport(code: (error as NSError).code, message: error.localizedDescription)
        }
    }

    private func makeRequest(for endpoint: Endpoint) throws -> URLRequest {
        let url = try makeURL(for: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.get.rawValue
        request.timeoutInterval = configuration.timeoutInterval
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let userAgent = configuration.userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        return request
    }

    private func makeURL(for endpoint: Endpoint) throws -> URL {
        var url = configuration.baseURL
        for component in endpoint.pathComponents {
            url = url.appendingPathComponent(component)
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw LyricsKitError.invalidResponse
        }

        components.queryItems = endpoint.queryItems.isEmpty ? nil : endpoint.queryItems

        guard let finalURL = components.url else {
            throw LyricsKitError.invalidResponse
        }

        return finalURL
    }

    private static func decodeErrorPayload(from data: Data, decoder: JSONDecoder) -> LRCLIBErrorResponse? {
        guard !data.isEmpty else { return nil }
        return try? decoder.decode(LRCLIBErrorResponse.self, from: data)
    }

    private static func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        guard let headerValue = response.value(forHTTPHeaderField: "Retry-After")?.lyricsKitTrimmed,
              !headerValue.isEmpty else {
            return nil
        }

        if let seconds = TimeInterval(headerValue) {
            return max(0, seconds)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"

        guard let date = formatter.date(from: headerValue) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }

    private enum Endpoint {
        case trackSignature(TrackSignature)
        case trackID(Int)
        case search(LyricsSearchQuery)

        func validate() throws {
            switch self {
            case let .trackSignature(signature):
                guard signature.isValid else {
                    throw LyricsKitError.invalidTrackSignature
                }
            case let .trackID(identifier):
                guard identifier > 0 else {
                    throw LyricsKitError.invalidLyricsIdentifier
                }
            case let .search(query):
                guard query.isValid else {
                    throw LyricsKitError.invalidSearchQuery
                }
            }
        }

        var pathComponents: [String] {
            switch self {
            case .trackSignature:
                return ["get"]
            case let .trackID(id):
                return ["get", String(id)]
            case .search:
                return ["search"]
            }
        }

        var queryItems: [URLQueryItem] {
            switch self {
            case let .trackSignature(signature):
                return signature.normalized().queryItems
            case .trackID:
                return []
            case let .search(query):
                return query.normalized().queryItems
            }
        }
    }
}

extension LRCLIBClient: LyricsProvider {
    public nonisolated var sourceName: String {
        "LRCLIB"
    }
}
