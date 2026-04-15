import Foundation
import Testing
@testable import LyricsKit

private final class RecordingURLProtocol: URLProtocol {
    private struct Registration {
        let handler: (URLRequest) throws -> (HTTPURLResponse, Data)
        var requestTimes: [Date] = []
    }

    private nonisolated(unsafe) static var registrations: [String: Registration] = [:]
    private static let lock = NSLock()

    static func register(
        token: String,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        lock.lock()
        registrations[token] = Registration(handler: handler)
        lock.unlock()
    }

    static func requestTimes(for token: String) -> [Date] {
        lock.lock()
        defer { lock.unlock() }
        return registrations[token]?.requestTimes ?? []
    }

    static func clear(token: String) {
        lock.lock()
        registrations[token] = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let token = request.value(forHTTPHeaderField: "User-Agent") ?? ""

        Self.lock.lock()
        guard var registration = Self.registrations[token] else {
            Self.lock.unlock()
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        registration.requestTimes.append(Date())
        let handler = registration.handler
        Self.registrations[token] = registration
        Self.lock.unlock()

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Test func lyricsBySignature_buildsTheCorrectRequestAndDecodesTheResponse() async throws {
    let expectedJSON = """
    {
      "id": 3396226,
      "trackName": "I Want to Live",
      "artistName": "Borislav Slavov",
      "albumName": "Baldur's Gate 3 (Original Game Soundtrack)",
      "duration": 233,
      "instrumental": false,
      "plainLyrics": "I feel your breath upon my neck",
            "syncedLyrics": "[00:01.00] I feel your breath upon my neck\\n[00:02.50] The clock won't stop"
    }
    """.data(using: .utf8)!

    let fixture = makeClient { request in
        let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        #expect(components.path == "/api/get")

        let queryItems = try #require(components.queryItems)
        #expect(queryItems == [
            URLQueryItem(name: "track_name", value: "I Want to Live"),
            URLQueryItem(name: "artist_name", value: "Borislav Slavov"),
            URLQueryItem(name: "album_name", value: "Baldur's Gate 3 (Original Game Soundtrack)"),
            URLQueryItem(name: "duration", value: "233")
        ])

        return (httpResponse(url: request.url!, statusCode: 200), expectedJSON)
    }

    let record = try await fixture.kit.lyrics(
        trackName: "I Want to Live",
        artistName: "Borislav Slavov",
        albumName: "Baldur's Gate 3 (Original Game Soundtrack)",
        durationInSeconds: 233
    )

    #expect(record.id == 3396226)
    #expect(record.trackName == "I Want to Live")
    #expect(record.parsedSyncedLyrics?.lines.count == 2)
    #expect(record.parsedSyncedLyrics?.line(at: 1.5)?.text == "I feel your breath upon my neck")
    #expect(record.parsedSyncedLyrics?.line(at: 3.0)?.text == "The clock won't stop")
}

@Test func lyricsByID_requestsTheSpecificRecord() async throws {
    let expectedJSON = """
    {
      "id": 42,
      "trackName": "Track 42",
      "artistName": "Artist",
      "albumName": "Album",
      "duration": 123,
      "instrumental": true,
      "plainLyrics": null,
      "syncedLyrics": null
    }
    """.data(using: .utf8)!

    let fixture = makeClient { request in
        let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        #expect(components.path == "/api/get/42")
        #expect(components.queryItems == nil)

        return (httpResponse(url: request.url!, statusCode: 200), expectedJSON)
    }

    let record = try await fixture.client.lyrics(id: 42)

    #expect(record.id == 42)
    #expect(record.instrumental)
}

@Test func searchBuildsTheExpectedQuery() async throws {
    let expectedJSON = """
    [
      {
        "id": 1,
        "trackName": "Still Alive",
        "artistName": "Jonathan Coulton",
        "albumName": "Portal",
        "duration": 182,
        "instrumental": false,
        "plainLyrics": "This was a triumph",
        "syncedLyrics": null
      },
      {
        "id": 2,
        "trackName": "Want You Gone",
        "artistName": "Jonathan Coulton",
        "albumName": "Portal 2",
        "duration": 156,
        "instrumental": false,
        "plainLyrics": null,
        "syncedLyrics": null
      }
    ]
    """.data(using: .utf8)!

    let fixture = makeClient { request in
        let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        #expect(components.path == "/api/search")

        let queryItems = try #require(components.queryItems)
        #expect(queryItems == [
            URLQueryItem(name: "q", value: "portal"),
            URLQueryItem(name: "artist_name", value: "Jonathan Coulton")
        ])

        return (httpResponse(url: request.url!, statusCode: 200), expectedJSON)
    }

    let records = try await fixture.kit.search(query: "portal", artistName: "Jonathan Coulton")

    #expect(records.count == 2)
    #expect(records.first?.trackName == "Still Alive")
}

@Test func lyricsKitBestLyricsPrefersSyncedSearchResult() async throws {
        let directJSON = """
        {
            "id": 100,
            "trackName": "I Want to Live",
            "artistName": "Borislav Slavov",
            "albumName": "Baldur's Gate 3 (Original Game Soundtrack)",
            "duration": 233,
            "instrumental": false,
            "plainLyrics": "I feel your breath upon my neck",
            "syncedLyrics": null
        }
        """.data(using: .utf8)!

        let searchJSON = """
        [
            {
                "id": 101,
                "trackName": "I Want to Live",
                "artistName": "Borislav Slavov",
                "albumName": "Baldur's Gate 3 (Original Game Soundtrack)",
                "duration": 233,
                "instrumental": false,
                "plainLyrics": "I feel your breath upon my neck",
                "syncedLyrics": null
            },
            {
                "id": 102,
                "trackName": "I Want to Live",
                "artistName": "Borislav Slavov",
                "albumName": "Baldur's Gate 3 (Original Game Soundtrack)",
                "duration": 235,
                "instrumental": false,
                "plainLyrics": "I feel your breath upon my neck",
                "syncedLyrics": "[00:01.00] I feel your breath upon my neck\\n[00:02.50] The clock won't stop"
            }
        ]
        """.data(using: .utf8)!

        let fixture = makeClient { request in
                let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))

                switch components.path {
                case "/api/get":
                        return (httpResponse(url: request.url!, statusCode: 200), directJSON)
                case "/api/search":
                        return (httpResponse(url: request.url!, statusCode: 200), searchJSON)
                default:
                        throw URLError(.badURL)
                }
        }

        let record = try await fixture.kit.bestLyrics(
                trackName: "I Want to Live",
                artistName: "Borislav Slavov",
                albumName: "Baldur's Gate 3 (Original Game Soundtrack)",
                durationInSeconds: 233
        )

        #expect(record?.id == 102)
        #expect(record?.hasSyncedLyrics == true)
}

@Test func lyricsRecordDecodesFractionalDurationValues() throws {
    let json = #"""
        {
            "id": 3396226,
            "trackName": "I Want to Live",
            "artistName": "Borislav Slavov",
            "albumName": "Baldur's Gate 3 (Original Game Soundtrack)",
            "duration": 340.741224,
            "instrumental": false,
            "plainLyrics": "I feel your breath upon my neck",
            "syncedLyrics": "[00:01.00] I feel your breath upon my neck\n[00:02.50] The clock won't stop"
        }
    """#.data(using: .utf8)!

        let record = try JSONDecoder().decode(LyricsRecord.self, from: json)

        #expect(record.duration == 341)
        #expect(record.parsedSyncedLyrics?.lines.count == 2)
}

@Test func searchSyncedFiltersUnsyncedResults() async throws {
        let searchJSON = """
        [
            {
                "id": 201,
                "trackName": "Still Alive",
                "artistName": "Jonathan Coulton",
                "albumName": "Portal",
                "duration": 182,
                "instrumental": false,
                "plainLyrics": "This was a triumph",
                "syncedLyrics": null
            },
            {
                "id": 202,
                "trackName": "Still Alive",
                "artistName": "Jonathan Coulton",
                "albumName": "Portal",
                "duration": 182,
                "instrumental": false,
                "plainLyrics": "This was a triumph",
                "syncedLyrics": "[00:01.00] This was a triumph"
            }
        ]
        """.data(using: .utf8)!

        let fixture = makeClient { request in
                let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
                #expect(components.path == "/api/search")
                return (httpResponse(url: request.url!, statusCode: 200), searchJSON)
        }

        let records = try await fixture.kit.searchSynced(trackName: "Still Alive", artistName: "Jonathan Coulton")

        #expect(records.count == 1)
        #expect(records.first?.id == 202)
}

@Test func parsedLyricsParsesMultipleTimeTagsAndSupportsPlaybackLookup() throws {
    let parsed = ParsedLyrics(syncedLyrics: """
    [00:00.50][00:01.25] Intro
    [00:02.00] Verse
    """)

    let lines = try #require(parsed?.lines)
    #expect(lines.map(\.timestamp) == [0.5, 1.25, 2.0])
        #expect(parsed?.currentLine(at: 0.75)?.text == "Intro")
        #expect(parsed?.nextLine(after: 0.75)?.text == "Intro")
        #expect(parsed?.nextLine(after: 1.30)?.text == "Verse")
        #expect(parsed?.previousLine(before: 2.50)?.text == "Verse")
        #expect(parsed?.timeRange?.lowerBound == 0.5)
        #expect(parsed?.timeRange?.upperBound == 2.0)
        #expect(parsed?.progress(at: 1.0, within: 2.0) == 0.5)
}

@Test func rateLimiterSpreadsBackToBackRequests() async throws {
    let expectedJSON = """
    {
      "id": 1,
      "trackName": "Track",
      "artistName": "Artist",
      "albumName": "Album",
      "duration": 100,
      "instrumental": false,
      "plainLyrics": null,
      "syncedLyrics": null
    }
    """.data(using: .utf8)!

    let fixture = makeClient(minimumRequestInterval: 0.25) { request in
        return (httpResponse(url: request.url!, statusCode: 200), expectedJSON)
    }

    let client = fixture.client
    async let first = client.lyrics(id: 1)
    async let second = client.lyrics(id: 2)
    _ = try await (first, second)

    let timestamps = RecordingURLProtocol.requestTimes(for: fixture.token)
    #expect(timestamps.count == 2)

    let interval = timestamps[1].timeIntervalSince(timestamps[0])
    #expect(interval >= 0.20)
}

@Test func providerConvenienceMethodsWorkForAnyProvider() async throws {
    let syncedRecord = LyricsRecord(
        id: 9001,
        trackName: "I Want to Live",
        artistName: "Borislav Slavov",
        albumName: "Baldur's Gate 3 (Original Game Soundtrack)",
        duration: 233,
        instrumental: false,
        plainLyrics: "I feel your breath upon my neck",
        syncedLyrics: "[00:01.00] I feel your breath upon my neck\n[00:02.50] The clock won't stop"
    )

    let unsyncedRecord = LyricsRecord(
        id: 9002,
        trackName: "I Want to Live",
        artistName: "Borislav Slavov",
        albumName: "Baldur's Gate 3 (Original Game Soundtrack)",
        duration: 233,
        instrumental: false,
        plainLyrics: "I feel your breath upon my neck",
        syncedLyrics: nil
    )

    let provider = MockLyricsProvider(
        sourceName: "Mock",
        exactRecord: syncedRecord,
        searchResults: [unsyncedRecord, syncedRecord]
    )

    let syncedResults = try await provider.searchSynced(trackName: "I Want to Live", artistName: "Borislav Slavov")
    #expect(syncedResults.count == 1)
    #expect(syncedResults.first?.id == 9001)

    let bestMatch = try await provider.searchBestMatch(
        trackName: "I Want to Live",
        artistName: "Borislav Slavov",
        albumName: "Baldur's Gate 3 (Original Game Soundtrack)",
        durationInSeconds: 233
    )
    #expect(bestMatch?.id == 9001)

    let parsed = try await provider.parsedLyrics(
        trackName: "I Want to Live",
        artistName: "Borislav Slavov",
        albumName: "Baldur's Gate 3 (Original Game Soundtrack)",
        durationInSeconds: 233
    )
    #expect(parsed?.timedLyrics.count == 2)
    #expect(provider.sourceName == "Mock")
}

private struct ClientFixture: @unchecked Sendable {
    let kit: LyricsKit
    let token: String

    var client: LRCLIBClient {
        kit.lrclib
    }
}

private func makeClient(
    minimumRequestInterval: TimeInterval = 0,
    handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
) -> ClientFixture {
    let token = UUID().uuidString
    RecordingURLProtocol.register(token: token, handler: handler)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RecordingURLProtocol.self]
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

    let session = URLSession(configuration: configuration)
    let clientConfiguration = LRCLIBClient.Configuration(
        minimumRequestInterval: minimumRequestInterval,
        timeoutInterval: 5,
        userAgent: token
    )

    return ClientFixture(
        kit: LyricsKit(configuration: LyricsKit.Configuration(
            baseURL: clientConfiguration.baseURL,
            minimumRequestInterval: clientConfiguration.minimumRequestInterval,
            timeoutInterval: clientConfiguration.timeoutInterval,
            userAgent: clientConfiguration.userAgent
        ), session: session),
        token: token
    )
}

private func httpResponse(url: URL, statusCode: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
}

private struct MockLyricsProvider: LyricsProvider {
    let sourceName: String
    let exactRecord: LyricsRecord
    let searchResults: [LyricsRecord]

    func lyrics(for signature: TrackSignature) async throws -> LyricsRecord {
        exactRecord
    }

    func lyrics(id: Int) async throws -> LyricsRecord {
        exactRecord
    }

    func search(_ query: LyricsSearchQuery) async throws -> [LyricsRecord] {
        searchResults
    }
}
