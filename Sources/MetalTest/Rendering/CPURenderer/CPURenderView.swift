import AppKit
import QuartzCore

final class CPURenderView: NSView {
    var scene: SceneRenderable? {
        didSet { startTime = CACurrentMediaTime(); lastFrameTime = startTime }
    }

    let fpsCounter = FPSCounter()
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var lastFrameTime: CFTimeInterval = 0
    private var bitmapContext: CGContext?
    private var bitmapSize: CGSize = .zero
    private let renderQueue = DispatchQueue(label: "cpu-render", qos: .userInteractive)
    private var isRendering = false

    /// Resolution scale (1.0 = full native). Rendering is on a background thread so UI stays responsive.
    private let resolutionScale: CGFloat = 1.0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.magnificationFilter = .trilinear
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
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

    @objc private func renderFrame(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let deltaTime = now - lastFrameTime
        let time = now - startTime
        lastFrameTime = now

        guard let scene, !isRendering else { return }

        let backingSize = convertToBacking(bounds.size)
        let renderW = max(1, Int(backingSize.width * resolutionScale))
        let renderH = max(1, Int(backingSize.height * resolutionScale))
        let renderSize = CGSize(width: renderW, height: renderH)

        // Recreate bitmap context if size changed
        if bitmapSize != renderSize {
            bitmapSize = renderSize
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            bitmapContext = CGContext(
                data: nil, width: renderW, height: renderH,
                bitsPerComponent: 8, bytesPerRow: renderW * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        }

        guard let ctx = bitmapContext else { return }

        // Update scene state on main thread (fast)
        scene.update(deltaTime: deltaTime, time: time, size: renderSize)

        // Render on background thread to keep UI responsive
        isRendering = true
        renderQueue.async { [weak self] in
            ctx.saveGState()
            scene.drawCPU(context: ctx, size: renderSize)
            ctx.restoreGState()

            let image = ctx.makeImage()

            DispatchQueue.main.async {
                self?.layer?.contents = image
                self?.isRendering = false
                self?.fpsCounter.recordFrame()
            }
        }
    }

    deinit {
        stopDisplayLink()
    }
}
