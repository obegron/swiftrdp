import Foundation
import CoreGraphics

class RDPManager: NSObject, ObservableObject, SwiftRDPBridgeDelegate {
    private let bridge = SwiftRDPBridge()
    private let connectionQueue = DispatchQueue(label: "SwiftRDP.connection")
    private let frameLock = NSLock()
    private var isRunning = false
    private var pendingImage: CGImage?
    private var pendingRemoteSize = CGSize(width: 16, height: 10)
    private var frameUpdateScheduled = false
    @Published var image: CGImage?
    @Published var status = "Disconnected"
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var remoteSize = CGSize(width: 16, height: 10)

    override init() {
        super.init()
        bridge.delegate = self
    }
    
    func connect(host: String, port: Int32 = 3389, user: String, pass: String?, settings: RDPConnectionSettings) {
        guard !isConnecting else {
            return
        }

        let password = pass ?? ""
        guard !password.isEmpty else {
            status = "Enter a password"
            return
        }

        DispatchQueue.main.async {
            self.status = "Connecting to \(host)..."
            self.isConnected = false
            self.isConnecting = true
        }

        connectionQueue.async {
            print("Connecting to \(host)...")
            self.isRunning = false
            let success = self.bridge.connect(
                toHost: host,
                port: port,
                user: user,
                password: password,
                width: settings.width,
                height: settings.height,
                colorDepth: settings.colorDepth,
                enableRemoteFx: settings.enableRemoteFx,
                sharedFolderName: settings.sharedFolderName ?? "",
                sharedFolderPath: settings.sharedFolderPath ?? ""
            )
            let error = self.bridge.lastErrorDescription() ?? "Unknown FreeRDP error"

            DispatchQueue.main.async {
                self.isConnected = success
                self.isConnecting = false
                self.status = success ? "Connected to \(host)" : "Failed to connect: \(error)"
            }

            if success {
                self.isRunning = true
                print("Successfully connected!")
                self.scheduleProcessLoop()
            } else {
                print("Failed to connect.")
            }
        }
    }

    func rdpBridge(_ bridge: SwiftRDPBridge, didUpdate image: CGImage, width: Int, height: Int) {
        frameLock.lock()
        pendingImage = image
        pendingRemoteSize = CGSize(width: width, height: height)
        if frameUpdateScheduled {
            frameLock.unlock()
            return
        }
        frameUpdateScheduled = true
        frameLock.unlock()

        DispatchQueue.main.async {
            self.frameLock.lock()
            let image = self.pendingImage
            let remoteSize = self.pendingRemoteSize
            self.pendingImage = nil
            self.frameUpdateScheduled = false
            self.frameLock.unlock()

            if let image {
                self.image = image
                self.remoteSize = remoteSize
            }
        }
    }

    func disconnect() {
        connectionQueue.async {
            self.isRunning = false
            self.bridge.disconnect()

            DispatchQueue.main.async {
                self.isConnected = false
                self.isConnecting = false
                self.status = "Disconnected"
            }
        }
    }

    func sendMouse(flags: UInt16, x: UInt16, y: UInt16) {
        connectionQueue.async {
            _ = self.bridge.sendMouseEvent(withFlags: flags, x: x, y: y)
        }
    }

    func sendUnicode(_ code: UInt16, down: Bool) {
        connectionQueue.async {
            _ = self.bridge.sendUnicodeKeyboardEvent(code, down: down)
        }
    }

    func sendScancode(_ scancode: UInt32, down: Bool) {
        connectionQueue.async {
            _ = self.bridge.sendKeyboardScancode(scancode, down: down)
        }
    }

    func sendAppleKeycode(_ keycode: UInt32, down: Bool) {
        connectionQueue.async {
            _ = self.bridge.sendAppleKeycode(keycode, down: down)
        }
    }
    
    private func scheduleProcessLoop() {
        connectionQueue.asyncAfter(deadline: .now() + 0.001) {
            guard self.isRunning else {
                return
            }

            if self.bridge.process() {
                self.scheduleProcessLoop()
                return
            }

            self.isRunning = false
            let error = self.bridge.lastErrorDescription() ?? "Disconnected"
            DispatchQueue.main.async {
                self.isConnected = false
                self.isConnecting = false
                self.status = error == "Disconnected" ? "Disconnected" : error
            }
        }
    }
}
