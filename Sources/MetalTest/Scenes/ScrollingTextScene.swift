import AppKit
import Metal
import CoreText
import ShaderTypes

final class ScrollingTextScene: SceneRenderable {
    let sceneType = DemoSceneType.scrollingText
    let vertexFunctionName = "text_vertex"
    let fragmentFunctionName = "text_fragment"
    let computeFunctionName: String? = nil

    private var time: Double = 0
    private var scrollOffset: Float = 0
    private var uniformBuffer: MTLBuffer?
    private var textTexture: MTLTexture?
    private let textureWidth = 1024
    private let textureHeight = 2048

    private let lines: [String] = {
        let phrases = [
            "Hello, Metal! Welcome to GPU rendering.",
            "The quick brown fox jumps over the lazy dog.",
            "Swift is a powerful and intuitive programming language.",
            "Metal provides near-direct access to the GPU.",
            "Core Graphics renders entirely on the CPU.",
            "Compare the frame rates side by side!",
            "func main() { print(\"Hello, World!\") }",
            "let device = MTLCreateSystemDefaultDevice()",
            "CGContext draws paths, fills, and strokes.",
            "The GPU processes thousands of fragments in parallel.",
            "import Metal; import MetalKit; import simd",
            "Vertex shaders transform geometry every frame.",
            "Fragment shaders compute per-pixel color values.",
            "CPU rendering is sequential but flexible.",
            "GPU rendering is parallel and blazingly fast.",
            "Lorem ipsum dolor sit amet, consectetur.",
            "Sed do eiusmod tempor incididunt ut labore.",
            "Ut enim ad minim veniam, quis nostrud.",
            "Duis aute irure dolor in reprehenderit.",
            "Excepteur sint occaecat cupidatat non proident.",
            "0xDEADBEEF 0xCAFEBABE 0x8BADF00D",
            "while (true) { render(); present(); }",
            "The cake is a lie. The shader is the truth.",
            "Roses are red, fragments are blue,",
            "GPUs are parallel, and so are you.",
            "SELECT * FROM pixels WHERE color = 'awesome';",
            "git commit -m 'Added more text to scroll'",
            "brew install metal-shaders --with-rainbow",
            "docker run -it ubuntu:latest /bin/bash",
            "System.out.println(\"Java has entered the chat\");",
        ]
        var result: [String] = []
        for _ in 0..<10 { result.append(contentsOf: phrases) }
        return result
    }()

    private let colors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow,
        .systemGreen, .systemTeal, .systemBlue,
        .systemPurple, .systemPink, .white,
        NSColor(red: 0.0, green: 1.0, blue: 0.5, alpha: 1),
        NSColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1),
        NSColor(red: 0.5, green: 0.5, blue: 1.0, alpha: 1),
    ]

    func update(deltaTime: Double, time: Double, size: CGSize) {
        self.time = time
        scrollOffset = Float(time * 0.05).truncatingRemainder(dividingBy: 1.0)
    }

    // MARK: - Metal

    func setupMetal(device: MTLDevice, library: MTLLibrary) {
        uniformBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.stride, options: .storageModeShared)
        textTexture = createTextTexture(device: device)
    }

    func drawMetal(encoder: MTLRenderCommandEncoder, size: CGSize) {
        guard let uniformBuffer, let textTexture else { return }
        var uniforms = Uniforms(
            time: Float(time),
            scrollOffset: scrollOffset,
            resolution: SIMD2<Float>(Float(size.width), Float(size.height))
        )
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(textTexture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }

    private func createTextTexture(device: MTLDevice) -> MTLTexture? {
        let w = textureWidth
        let h = textureHeight
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                   bitsPerComponent: 8, bytesPerRow: w * 4,
                                   space: colorSpace,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        // Dark background
        ctx.setFillColor(NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        let fontSize: CGFloat = 14
        let lineHeight: CGFloat = 20
        let totalLines = Int(CGFloat(h) / lineHeight)

        for i in 0..<totalLines {
            let text = lines[i % lines.count]
            let color = colors[i % colors.count]
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: color
            ]
            let str = NSAttributedString(string: text, attributes: attrs)
            let line = CTLineCreateWithAttributedString(str)
            let y = CGFloat(h) - CGFloat(i) * lineHeight - lineHeight
            ctx.textPosition = CGPoint(x: 10, y: y)
            CTLineDraw(line, ctx)
        }

        guard let image = ctx.makeImage() else { return nil }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: w, height: h,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }

        let region = MTLRegionMake2D(0, 0, w, h)
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }
        texture.replace(region: region, mipmapLevel: 0,
                        withBytes: ptr, bytesPerRow: w * 4)
        return texture
    }

    // MARK: - CPU Rendering

    func drawCPU(context: CGContext, size: CGSize) {
        let w = size.width
        let h = size.height

        // Dark background
        context.setFillColor(NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))

        let fontSize: CGFloat = 14
        let lineHeight: CGFloat = 20
        let totalVisibleLines = Int(h / lineHeight) + 2
        let scrollPixels = CGFloat(scrollOffset) * CGFloat(lines.count) * lineHeight

        for i in 0..<totalVisibleLines {
            let globalLine = i + Int(scrollPixels / lineHeight)
            let lineIndex = ((globalLine % lines.count) + lines.count) % lines.count
            let text = lines[lineIndex]
            let color = colors[lineIndex % colors.count]

            let y = h - CGFloat(i) * lineHeight + scrollPixels.truncatingRemainder(dividingBy: lineHeight)

            if y < -lineHeight || y > h + lineHeight { continue }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: color
            ]
            let str = NSAttributedString(string: text, attributes: attrs)
            let line = CTLineCreateWithAttributedString(str)
            context.textPosition = CGPoint(x: 10, y: y)
            CTLineDraw(line, context)
        }
    }
}
