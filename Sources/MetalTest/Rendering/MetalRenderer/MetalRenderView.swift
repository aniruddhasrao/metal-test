import AppKit
import Metal
import QuartzCore
import ShaderTypes

final class MetalRenderView: NSView {
    var scene: SceneRenderable? {
        didSet {
            if let scene, let device, let library {
                scene.setupMetal(device: device, library: library)
                rebuildPipeline(for: scene)
            }
            startTime = CACurrentMediaTime()
            lastFrameTime = startTime
        }
    }

    let fpsCounter = FPSCounter()
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var library: MTLLibrary?
    private var metalLayer: CAMetalLayer?
    private var renderPipeline: MTLRenderPipelineState?
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var lastFrameTime: CFTimeInterval = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupMetal()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        self.metalLayer = layer
        return layer
    }

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }
        self.device = device
        self.commandQueue = device.makeCommandQueue()

        // Load metallib from next to the executable
        let execPath = ProcessInfo.processInfo.arguments[0]
        let execDir = (execPath as NSString).deletingLastPathComponent
        let libPath = execDir + "/default.metallib"
        if let lib = try? device.makeLibrary(URL: URL(fileURLWithPath: libPath)) {
            self.library = lib
        } else {
            // Fallback: try default library
            self.library = device.makeDefaultLibrary()
        }

        if library == nil {
            print("Failed to load Metal library from \(libPath)")
        }

        metalLayer?.device = device
        metalLayer?.pixelFormat = .bgra8Unorm
        metalLayer?.framebufferOnly = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            metalLayer?.contentsScale = window?.backingScaleFactor ?? 2.0
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }

    override func layout() {
        super.layout()
        let backingSize = convertToBacking(bounds.size)
        metalLayer?.drawableSize = backingSize
    }

    private func startDisplayLink() {
        stopDisplayLink()
        startTime = CACurrentMediaTime()
        lastFrameTime = startTime
        displayLink = self.displayLink(target: self, selector: #selector(renderFrame(_:)))
        displayLink?.add(to: .current, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func rebuildPipeline(for scene: SceneRenderable) {
        guard let device, let library else { return }

        guard let vertexFn = library.makeFunction(name: scene.vertexFunctionName),
              let fragFn = library.makeFunction(name: scene.fragmentFunctionName) else {
            print("Failed to load shader functions: \(scene.vertexFunctionName), \(scene.fragmentFunctionName)")
            return
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFn
        desc.fragmentFunction = fragFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            renderPipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }

    @objc private func renderFrame(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let deltaTime = now - lastFrameTime
        let time = now - startTime
        lastFrameTime = now

        guard let scene, let commandQueue, let metalLayer,
              let drawable = metalLayer.nextDrawable(),
              let renderPipeline else { return }

        let size = metalLayer.drawableSize
        scene.update(deltaTime: deltaTime, time: time, size: CGSize(width: size.width, height: size.height))

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // Compute pass (if needed)
        scene.computeMetal(commandBuffer: commandBuffer, size: CGSize(width: size.width, height: size.height))

        // Render pass
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = drawable.texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        passDesc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else { return }
        encoder.setRenderPipelineState(renderPipeline)
        scene.drawMetal(encoder: encoder, size: CGSize(width: size.width, height: size.height))
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()

        fpsCounter.recordFrame()
    }

    deinit {
        stopDisplayLink()
    }
}
