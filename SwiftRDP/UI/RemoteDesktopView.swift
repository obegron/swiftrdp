import AppKit
import SwiftUI

private enum RDPInput {
    static let ptrFlagsWheel: UInt16 = 0x0200
    static let ptrFlagsHWheel: UInt16 = 0x0400
    static let ptrFlagsWheelNegative: UInt16 = 0x0100
    static let ptrFlagsMove: UInt16 = 0x0800
    static let ptrFlagsDown: UInt16 = 0x8000
    static let ptrFlagsButton1: UInt16 = 0x1000
    static let ptrFlagsButton2: UInt16 = 0x2000
    static let ptrFlagsButton3: UInt16 = 0x4000
}

struct RemoteDesktopView: NSViewRepresentable {
    let image: CGImage?
    let remoteSize: CGSize
    let onMouse: (UInt16, UInt16, UInt16) -> Void
    let onUnicode: (UInt16, Bool) -> Void
    let onScancode: (UInt32, Bool) -> Void
    let onAppleKeycode: (UInt32, Bool) -> Void

    func makeNSView(context: Context) -> RemoteDesktopScrollView {
        let view = RemoteDesktopScrollView()
        view.remoteView.onMouse = onMouse
        view.remoteView.onUnicode = onUnicode
        view.remoteView.onScancode = onScancode
        view.remoteView.onAppleKeycode = onAppleKeycode
        return view
    }

    func updateNSView(_ view: RemoteDesktopScrollView, context: Context) {
        view.remoteView.image = image
        view.remoteView.remoteSize = remoteSize
        view.remoteView.onMouse = onMouse
        view.remoteView.onUnicode = onUnicode
        view.remoteView.onScancode = onScancode
        view.remoteView.onAppleKeycode = onAppleKeycode
        view.updateRemoteLayout(remoteSize: remoteSize)
        view.remoteView.needsDisplay = true
    }
}

final class RemoteDesktopScrollView: NSScrollView {
    let remoteView = RemoteDesktopNSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = true
        backgroundColor = .black
        borderType = .noBorder
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        documentView = remoteView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateRemoteLayout(remoteSize: remoteView.remoteSize)
    }

    override func layout() {
        super.layout()
        updateRemoteLayout(remoteSize: remoteView.remoteSize)
    }

    func updateRemoteLayout(remoteSize: CGSize) {
        hasHorizontalScroller = false
        hasVerticalScroller = false
        remoteView.scaleToBounds = true
        remoteView.frame = contentView.bounds
    }
}

final class RemoteDesktopNSView: NSView {
    var image: CGImage?
    var remoteSize = CGSize(width: 16, height: 10)
    var scaleToBounds = false
    var onMouse: ((UInt16, UInt16, UInt16) -> Void)?
    var onUnicode: ((UInt16, Bool) -> Void)?
    var onScancode: ((UInt32, Bool) -> Void)?
    var onAppleKeycode: ((UInt32, Bool) -> Void)?
    private var trackingAreaRef: NSTrackingArea?
    private var pressedModifierKeycodes = Set<UInt16>()

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
        super.updateTrackingAreas()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()

        guard let image else {
            return
        }

        guard let graphicsContext = NSGraphicsContext.current else {
            return
        }

        let scaled = abs(imageRect.width - CGFloat(image.width)) > 0.5 ||
            abs(imageRect.height - CGFloat(image.height)) > 0.5
        graphicsContext.imageInterpolation = scaled ? .high : .none
        let context = graphicsContext.cgContext
        context.saveGState()
        context.translateBy(x: 0, y: imageRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: CGPoint(x: imageRect.minX, y: 0), size: imageRect.size))
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendPointer(event, flags: RDPInput.ptrFlagsDown | RDPInput.ptrFlagsButton1)
    }

    override func mouseUp(with event: NSEvent) {
        sendPointer(event, flags: RDPInput.ptrFlagsButton1)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendPointer(event, flags: RDPInput.ptrFlagsDown | RDPInput.ptrFlagsButton2)
    }

    override func rightMouseUp(with event: NSEvent) {
        sendPointer(event, flags: RDPInput.ptrFlagsButton2)
    }

    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendPointer(event, flags: RDPInput.ptrFlagsDown | RDPInput.ptrFlagsButton3)
    }

    override func otherMouseUp(with event: NSEvent) {
        sendPointer(event, flags: RDPInput.ptrFlagsButton3)
    }

    override func mouseMoved(with event: NSEvent) {
        sendPointer(event, flags: RDPInput.ptrFlagsMove)
    }

    override func mouseDragged(with event: NSEvent) {
        sendPointer(event, flags: RDPInput.ptrFlagsMove)
    }

    override func rightMouseDragged(with event: NSEvent) {
        sendPointer(event, flags: RDPInput.ptrFlagsMove)
    }

    override func otherMouseDragged(with event: NSEvent) {
        sendPointer(event, flags: RDPInput.ptrFlagsMove)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let point = remotePoint(for: event) else {
            return
        }

        sendScroll(delta: Int(event.scrollingDeltaY), wheelFlag: RDPInput.ptrFlagsWheel, at: point)
        sendScroll(delta: Int(event.scrollingDeltaX), wheelFlag: RDPInput.ptrFlagsHWheel, at: point)
    }

    override func keyDown(with event: NSEvent) {
        _ = sendSpecialKey(event, down: true)
    }

    override func keyUp(with event: NSEvent) {
        _ = sendSpecialKey(event, down: false)
    }

    override func flagsChanged(with event: NSEvent) {
        if event.keyCode == 57 {
            sendAppleKeycode(event.keyCode, down: true)
            sendAppleKeycode(event.keyCode, down: false)
            return
        }

        guard let flag = modifierFlag(for: event.keyCode) else {
            super.flagsChanged(with: event)
            return
        }

        let isDown = event.modifierFlags.contains(flag)
        let wasDown = pressedModifierKeycodes.contains(event.keyCode)

        if isDown && !wasDown {
            pressedModifierKeycodes.insert(event.keyCode)
            sendAppleKeycode(event.keyCode, down: true)
        } else if !isDown && wasDown {
            pressedModifierKeycodes.remove(event.keyCode)
            sendAppleKeycode(event.keyCode, down: false)
        }
    }

    private var imageRect: CGRect {
        if !scaleToBounds {
            return CGRect(origin: .zero, size: remoteSize)
        }

        let size = bounds.size
        let remoteAspect = max(1, remoteSize.width) / max(1, remoteSize.height)
        let localAspect = max(1, size.width) / max(1, size.height)

        if localAspect > remoteAspect {
            let width = size.height * remoteAspect
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
        }

        let height = size.width / remoteAspect
        return CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
    }

    private func sendPointer(_ event: NSEvent, flags: UInt16) {
        guard let point = remotePoint(for: event) else {
            return
        }
        onMouse?(flags, point.x, point.y)
    }

    private func sendScroll(delta: Int, wheelFlag: UInt16, at point: (x: UInt16, y: UInt16)) {
        guard delta != 0 else {
            return
        }

        let amount = UInt16(min(0x01ff, max(1, abs(delta) * 24)))
        let direction: UInt16 = delta < 0 ? RDPInput.ptrFlagsWheelNegative : 0
        onMouse?(wheelFlag | direction | amount, point.x, point.y)
    }

    private func remotePoint(for event: NSEvent) -> (x: UInt16, y: UInt16)? {
        let location = convert(event.locationInWindow, from: nil)
        let rect = imageRect
        guard rect.contains(location) else {
            return nil
        }

        let x = ((location.x - rect.minX) / rect.width) * remoteSize.width
        let y = ((location.y - rect.minY) / rect.height) * remoteSize.height
        let remoteX = UInt16(min(Int(UInt16.max), max(0, Int(x.rounded(.down)))))
        let remoteY = UInt16(min(Int(UInt16.max), max(0, Int(y.rounded(.down)))))
        return (remoteX, remoteY)
    }

    private func sendSpecialKey(_ event: NSEvent, down: Bool) -> Bool {
        sendAppleKeycode(event.keyCode, down: down)
        return true
    }

    private func sendAppleKeycode(_ keyCode: UInt16, down: Bool) {
        onAppleKeycode?(UInt32(keyCode), down)
    }

    private func modifierFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 56, 60:
            return .shift
        case 59, 62:
            return .control
        case 58, 61:
            return .option
        case 54, 55:
            return .command
        default:
            return nil
        }
    }
}
