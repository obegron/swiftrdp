import Foundation

struct RDPConnectionSettings {
    var width: Int32
    var height: Int32
    var colorDepth: Int32
    var enableRemoteFx: Bool
    var enableAudioPlayback: Bool
    var sharedFolderName: String?
    var sharedFolderPath: String?
}

struct ResolutionOption: Identifiable, Hashable {
    var id: String { label }
    let label: String
    let width: Int32
    let height: Int32

    static let all: [ResolutionOption] = [
        ResolutionOption(label: "1024 x 768", width: 1024, height: 768),
        ResolutionOption(label: "1280 x 720", width: 1280, height: 720),
        ResolutionOption(label: "1366 x 768", width: 1366, height: 768),
        ResolutionOption(label: "1600 x 900", width: 1600, height: 900),
        ResolutionOption(label: "1920 x 1080", width: 1920, height: 1080)
    ]
}
