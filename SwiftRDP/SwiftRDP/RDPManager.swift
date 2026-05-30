import Foundation
import CoreGraphics

class RDPManager: NSObject, ObservableObject, SwiftRDPBridgeDelegate {
    private struct ConnectionParams {
        let host: String
        let port: Int32
        let user: String
        let password: String
        let settings: RDPConnectionSettings
    }

    private let bridge = SwiftRDPBridge()
    private let connectionQueue = DispatchQueue(label: "SwiftRDP.connection")
    private let bridgeLock = NSLock()
    private let frameLock = NSLock()
    private var isRunning = false
    private var userRequestedDisconnect = false
    private var reconnectAttempts = 0
    private var lastConnectionParams: ConnectionParams?
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

        let params = ConnectionParams(host: host, port: port, user: user, password: password, settings: settings)
        userRequestedDisconnect = false
        lastConnectionParams = params
        reconnectAttempts = 0
        connect(params)
    }

    private func connect(_ params: ConnectionParams) {
        DispatchQueue.main.async {
            self.status = "Connecting to \(params.host)..."
            self.isConnected = false
            self.isConnecting = true
        }

        connectionQueue.async {
            print("Connecting to \(params.host)...")
            self.isRunning = false
            self.bridgeLock.lock()
            let success = self.bridge.connect(
                toHost: params.host,
                port: params.port,
                user: params.user,
                password: params.password,
                width: params.settings.width,
                height: params.settings.height,
                colorDepth: params.settings.colorDepth,
                enableRemoteFx: params.settings.enableRemoteFx,
                enableAudioPlayback: params.settings.enableAudioPlayback,
                sharedFolderName: params.settings.sharedFolderName ?? "",
                sharedFolderPath: params.settings.sharedFolderPath ?? ""
            )
            let error = self.bridge.lastErrorDescription() ?? "Unknown FreeRDP error"
            self.bridgeLock.unlock()

            DispatchQueue.main.async {
                self.isConnected = success
                self.isConnecting = false
                self.status = success ? "Connected to \(params.host)" : "Failed to connect: \(error)"
            }

            if success {
                self.isRunning = true
                self.reconnectAttempts = 0
                print("Successfully connected!")
                self.scheduleProcessLoop()
            } else {
                print("Failed to connect.")
                self.handleUnexpectedDisconnect(error: error)
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
        userRequestedDisconnect = true
        reconnectAttempts = 0
        connectionQueue.async {
            self.isRunning = false
            self.clearFrame()
            self.bridgeLock.lock()
            self.bridge.disconnect()
            self.bridgeLock.unlock()

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
            self.handleUnexpectedDisconnect(error: error)
        }
    }

    private func handleUnexpectedDisconnect(error: String) {
        clearFrame()

        guard !userRequestedDisconnect, reconnectAttempts < 8, let params = lastConnectionParams else {
            reconnectAttempts = 0
            DispatchQueue.main.async {
                self.isConnected = false
                self.isConnecting = false
                self.status = error == "Disconnected" ? "Disconnected" : error
            }
            return
        }

        let delay = min(30.0, pow(2.0, Double(reconnectAttempts)))
        reconnectAttempts += 1
        DispatchQueue.main.async {
            self.isConnected = false
            self.isConnecting = false
            self.status = "Reconnecting in \(Int(delay))s (attempt \(self.reconnectAttempts))..."
        }

        connectionQueue.asyncAfter(deadline: .now() + delay) {
            guard !self.userRequestedDisconnect else {
                return
            }
            self.connect(params)
        }
    }

    private func clearFrame() {
        DispatchQueue.main.async {
            self.frameLock.lock()
            self.pendingImage = nil
            self.frameUpdateScheduled = false
            self.frameLock.unlock()
            self.image = nil
        }
    }
}
