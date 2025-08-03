import Foundation

// Represents the options for a download
struct DownloadOptions {
    var subtitles: Bool = false
    var thumbnail: Bool = false
    var metadata: Bool = false
    var playlist: Bool = false
}

// Represents the quality of the video to download
enum VideoQuality: String, CaseIterable, Identifiable {
    case best
    case p1080
    case p720
    case audio

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .best: return "Best"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .audio: return "Audio Only"
        }
    }
}

// Represents the information fetched from a video URL
// Conforms to Decodable to be parsed from yt-dlp's JSON output
struct VideoInfo: Decodable, Identifiable {
    var id: String
    var title: String
    var uploader: String?
    var duration: Int?
    var view_count: Int?
    var thumbnail: String? // URL of the thumbnail
}
