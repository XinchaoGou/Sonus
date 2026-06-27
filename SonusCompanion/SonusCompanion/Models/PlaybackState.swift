import Foundation

enum PlaybackState: String, Sendable {
    case idle = "Idle"
    case generating = "Generating"
    case playing = "Playing"
    case paused = "Paused"
    case error = "Error"
}
