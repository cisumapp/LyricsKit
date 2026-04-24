import Foundation

public enum LyricsDebugLogger {
    public nonisolated static func log(_ message: String) {
        #if os(iOS)
        let platform = "iOS"
        #elseif os(macOS)
        let platform = "macOS"
        #else
        let platform = "Apple"
        #endif

        print("[\(platform)-DEBUG] [LyricsKit] \(message)")
    }
}
