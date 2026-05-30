import MetalKit
import SwiftUI

struct MetalView: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.framebufferOnly = true
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {}
}
