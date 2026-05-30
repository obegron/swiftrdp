import Foundation
import Metal

struct HardwareCapabilities {
    let metalDeviceName: String?
    let supportsMetal3: Bool
    let freeRDPHasVideoToolbox: Bool

    static let current: HardwareCapabilities = {
        let device = MTLCreateSystemDefaultDevice()
        let supportsMetal3: Bool
        if #available(macOS 13.0, *) {
            supportsMetal3 = device?.supportsFamily(.metal3) ?? false
        } else {
            supportsMetal3 = false
        }

        return HardwareCapabilities(
            metalDeviceName: device?.name,
            supportsMetal3: supportsMetal3,
            freeRDPHasVideoToolbox: SwiftRDPBridge.freeRDPHasVideoToolboxSupport()
        )
    }()

    var shortLabel: String {
        let metal = supportsMetal3 ? "Metal 3" : (metalDeviceName == nil ? "No Metal" : "Metal")
        let video = freeRDPHasVideoToolbox ? "VT H.264" : "SW H.264"
        return "\(metal) / \(video)"
    }

    var detail: String {
        let device = metalDeviceName ?? "No Metal device"
        let video = freeRDPHasVideoToolbox ? "VideoToolbox H.264 decode enabled" : "VideoToolbox H.264 decode not compiled in"
        return "\(device) - \(video)"
    }
}
