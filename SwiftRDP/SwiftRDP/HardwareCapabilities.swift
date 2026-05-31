import Foundation

struct HardwareCapabilities {
    let freeRDPHasVideoToolbox: Bool

    static let current: HardwareCapabilities = {
        return HardwareCapabilities(
            freeRDPHasVideoToolbox: SwiftRDPBridge.freeRDPHasVideoToolboxSupport()
        )
    }()

    var shortLabel: String {
        freeRDPHasVideoToolbox ? "VT H.264" : "SW H.264"
    }

    var detail: String {
        freeRDPHasVideoToolbox ? "VideoToolbox H.264 decode enabled" : "VideoToolbox H.264 decode not compiled in"
    }
}
