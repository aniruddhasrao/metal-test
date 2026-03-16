import AppKit
import Metal

enum DemoSceneType: String, CaseIterable, Identifiable {
    case scenery = "3D Scenery"
    case scrollingText = "Scrolling Text"
    case particles = "Particles"
    var id: String { rawValue }
}

protocol SceneRenderable: AnyObject {
    var sceneType: DemoSceneType { get }

    /// Update animation state
    func update(deltaTime: Double, time: Double, size: CGSize)

    /// CPU rendering path
    func drawCPU(context: CGContext, size: CGSize)

    /// Metal rendering path - encode draw commands
    func drawMetal(encoder: MTLRenderCommandEncoder, size: CGSize)

    /// Optional: encode compute commands (e.g., particle update)
    func computeMetal(commandBuffer: MTLCommandBuffer, size: CGSize)

    /// Metal pipeline names this scene needs
    var vertexFunctionName: String { get }
    var fragmentFunctionName: String { get }
    var computeFunctionName: String? { get }

    /// Extra Metal setup (textures, buffers) — called once when scene is selected
    func setupMetal(device: MTLDevice, library: MTLLibrary)
}

extension SceneRenderable {
    func computeMetal(commandBuffer: MTLCommandBuffer, size: CGSize) {}
    var computeFunctionName: String? { nil }
    func setupMetal(device: MTLDevice, library: MTLLibrary) {}
}
