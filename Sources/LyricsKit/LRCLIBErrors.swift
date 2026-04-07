import Foundation

public struct LRCLIBErrorResponse: Codable, Sendable, Hashable {
    public let code: Int
    public let name: String
    public let message: String

    public init(code: Int, name: String, message: String) {
        self.code = code
        self.name = name
        self.message = message
    }
}

public enum LyricsKitError: Error, Sendable {
    case invalidTrackSignature
    case invalidSearchQuery
    case invalidLyricsIdentifier
    case invalidResponse
    case transport(code: Int, message: String)
    case notFound(LRCLIBErrorResponse?)
    case rateLimited(retryAfter: TimeInterval?, payload: LRCLIBErrorResponse?)
    case httpError(statusCode: Int, payload: LRCLIBErrorResponse?, retryAfter: TimeInterval?)
    case decodingFailed(message: String)
}

extension LyricsKitError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidTrackSignature:
            return "Track signature must include a non-empty track name, artist name, album name, and duration in seconds."
        case .invalidSearchQuery:
            return "Search query must include either q or track_name."
        case .invalidLyricsIdentifier:
            return "Lyrics identifiers must be positive integers."
        case .invalidResponse:
            return "LRCLIB returned an invalid response."
        case let .transport(code, message):
            return "Networking failed with code \(code): \(message)"
        case let .notFound(payload):
            return payload?.message ?? "LRCLIB could not find the requested lyrics."
        case let .rateLimited(retryAfter, payload):
            if let payload {
                if let retryAfter {
                    return "LRCLIB rate limited the request for \(retryAfter) seconds: \(payload.message)"
                }
                return payload.message
            }
            if let retryAfter {
                return "LRCLIB rate limited the request for \(retryAfter) seconds."
            }
            return "LRCLIB rate limited the request."
        case let .httpError(statusCode, payload, retryAfter):
            if let payload {
                if let retryAfter {
                    return "LRCLIB returned HTTP \(statusCode) and asked to retry after \(retryAfter) seconds: \(payload.message)"
                }
                return "LRCLIB returned HTTP \(statusCode): \(payload.message)"
            }
            if let retryAfter {
                return "LRCLIB returned HTTP \(statusCode) and asked to retry after \(retryAfter) seconds."
            }
            return "LRCLIB returned HTTP \(statusCode)."
        case let .decodingFailed(message):
            return "Failed to decode the LRCLIB response: \(message)"
        }
    }
}
