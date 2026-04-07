//
//  NetworkClient.swift
//  SDKit
//
//  Created by Aarav Gupta on 01/01/26.
//

import Foundation

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public actor NetworkClient {
    
    private let baseURL: String
    private let session: URLSession
    
    // init takes in baseURL
    public init(baseURL: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }
    
    // post/send method
    public func send<T: Decodable>(_ endpoint: String, body: Data? = nil) async throws -> T {
        let data = try await get(endpoint, body: body)
        let response = try JSONDecoder().decode(T.self, from: data)
        return response
    }
    
    // implement a get method
    // body to be sent is optional
    // returns data so manual parsing is required
    public func get(_ endpoint: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: baseURL) else { throw URLError(.badURL) }
        
        let finalURL = url.appendingPathComponent(endpoint)
        // Automatically handles "/" both "/myendpoint" and "myendpoint" work
        guard let url = URLComponents(url: finalURL, resolvingAgainstBaseURL: true)?.url else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        var httpMethod = HTTPMethod.get.rawValue
        
        if let body = body {
            request.httpBody = body
            httpMethod = "POST"
        }
        
        request.httpMethod = httpMethod

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data, let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }

                if httpResponse.statusCode != 200 {
                    if let errorString = String(data: data, encoding: .utf8) {
                        print("❌ SDKit: Network Error (\(httpResponse.statusCode)): \(errorString)")
                    }
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }

                continuation.resume(returning: data)
            }

            task.resume()
        }
    }
}
