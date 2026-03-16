import AppKit
import Metal
import ShaderTypes
import simd

final class SceneryScene: SceneRenderable {
    let sceneType = DemoSceneType.scenery
    let vertexFunctionName = "scenery_vertex"
    let fragmentFunctionName = "scenery_fragment"
    let computeFunctionName: String? = nil

    private var time: Double = 0
    private var uniformBuffer: MTLBuffer?

    func update(deltaTime: Double, time: Double, size: CGSize) {
        self.time = time
    }

    func setupMetal(device: MTLDevice, library: MTLLibrary) {
        uniformBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.stride, options: .storageModeShared)
    }

    func drawMetal(encoder: MTLRenderCommandEncoder, size: CGSize) {
        guard let uniformBuffer else { return }
        var uniforms = Uniforms(
            time: Float(time),
            scrollOffset: 0,
            resolution: SIMD2<Float>(Float(size.width), Float(size.height))
        )
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }

    // MARK: - CPU Rendering (per-pixel, matching Metal shader exactly)

    func drawCPU(context: CGContext, size: CGSize) {
        let w = Int(size.width)
        let h = Int(size.height)
        guard w > 0, h > 0 else { return }

        guard let data = context.data else { return }
        let buf = data.bindMemory(to: UInt32.self, capacity: w * h)
        let bytesPerRow = context.bytesPerRow / 4
        let t = Float(time)

        for py in 0..<h {
            for px in 0..<w {
                let uvx = Float(px) / Float(w)
                // Bitmap row 0 is top of image, but uv.y=0 is bottom of scene
                let uvy = 1.0 - Float(py) / Float(h)

                let col = sceneryPixel(uvx: uvx, uvy: uvy, t: t)

                let r = UInt32(min(max(col.x * 255, 0), 255))
                let g = UInt32(min(max(col.y * 255, 0), 255))
                let b = UInt32(min(max(col.z * 255, 0), 255))

                // BGRA little-endian (premultipliedFirst + byteOrder32Little = BGRA)
                buf[py * bytesPerRow + px] = (255 << 24) | (r << 16) | (g << 8) | b
            }
        }
    }

    // Direct port of the Metal fragment shader
    private func sceneryPixel(uvx: Float, uvy: Float, t: Float) -> SIMD3<Float> {
        let uv = SIMD2<Float>(uvx, uvy)

        // Sky gradient
        let skyTop = SIMD3<Float>(0.1, 0.15, 0.4)
        let skyBottom = SIMD3<Float>(0.5, 0.7, 0.9)
        var col = mix(skyBottom, skyTop, t: SIMD3<Float>(repeating: uv.y))

        // Sun
        let sunPos = SIMD2<Float>(0.75, 0.75 + 0.05 * sin(t * 0.3))
        let sunDist = length(uv - sunPos)
        let sun = smoothstep(0.08, 0.05, sunDist)
        let glow = smoothstep(0.3, 0.05, sunDist)
        col += SIMD3<Float>(1.0, 0.9, 0.3) * sun
        col += SIMD3<Float>(1.0, 0.7, 0.2) * glow * 0.3

        // Clouds
        for i in 0..<3 {
            let cy = 0.7 + Float(i) * 0.07
            let cp = SIMD2<Float>(uv.x * 3.0 + t * 0.05 * (1.0 + Float(i) * 0.5), cy * 2.0)
            var cloud = fbm(cp)
            cloud = smoothstep(0.4, 0.7, cloud)
            let white = SIMD3<Float>(1, 1, 1)
            let blend = cloud * 0.6 * smoothstep(0.5, 0.8, uv.y)
            col = mix(col, white, t: SIMD3<Float>(repeating: blend))
        }

        // Mountains - back layer
        let mtnH1 = 0.3 + 0.15 * fbm(SIMD2<Float>(uv.x * 2.0 + 1.0, 0.0))
        if uv.y < mtnH1 {
            let mtnCol = SIMD3<Float>(0.25, 0.2, 0.35)
            let blend = smoothstep(mtnH1, mtnH1 - 0.01, uv.y)
            col = mix(col, mtnCol, t: SIMD3<Float>(repeating: blend))
        }

        // Mountains - front layer
        let mtnH2 = 0.2 + 0.12 * fbm(SIMD2<Float>(uv.x * 3.0 + 5.0, 0.5))
        if uv.y < mtnH2 {
            let mtnCol = SIMD3<Float>(0.15, 0.12, 0.2)
            let blend = smoothstep(mtnH2, mtnH2 - 0.01, uv.y)
            col = mix(col, mtnCol, t: SIMD3<Float>(repeating: blend))
        }

        // Ground
        let groundLevel = 0.15 + 0.03 * sin(uv.x * 8.0 + 2.0)
        if uv.y < groundLevel {
            var groundCol = SIMD3<Float>(0.15, 0.4, 0.12)
            let grassNoise = noise(uv * 50.0)
            groundCol += SIMD3<Float>(0.0, 0.1, 0.0) * grassNoise
            col = groundCol
        }

        // Trees
        for i in 0..<8 {
            let tx: Float = 0.05 + Float(i) * 0.125
            let treeBase: Float = 0.15 + 0.03 * sin(tx * 8.0 + 2.0)

            // Trunk
            let trunkW: Float = 0.008
            let trunkH: Float = 0.06 + 0.02 * hash(SIMD2<Float>(Float(i), 0.0))
            if abs(uv.x - tx) < trunkW && uv.y > treeBase && uv.y < treeBase + trunkH {
                col = SIMD3<Float>(0.35, 0.2, 0.1)
            }

            // Canopy (triangle)
            let canopyBase = treeBase + trunkH
            let canopyH: Float = 0.08 + 0.03 * hash(SIMD2<Float>(Float(i), 1.0))
            let canopyW: Float = 0.04 + 0.02 * hash(SIMD2<Float>(Float(i), 2.0))
            let progress = (uv.y - canopyBase) / canopyH
            if uv.y > canopyBase && uv.y < canopyBase + canopyH {
                let halfW = canopyW * (1.0 - progress)
                if abs(uv.x - tx) < halfW {
                    let shade = 0.7 + 0.3 * progress
                    col = SIMD3<Float>(0.1, 0.45 * shade, 0.08)
                }
            }
        }

        // Water at very bottom
        if uv.y < 0.06 {
            let wave = sin(uv.x * 30.0 + t * 2.0) * 0.003
            let waterLine: Float = 0.06 + wave
            if uv.y < waterLine {
                var waterCol = SIMD3<Float>(0.1, 0.3, 0.6)
                let sparkle = powf(max(0.0, sin(uv.x * 60.0 + t * 3.0)), 20.0) * 0.5
                waterCol += SIMD3<Float>(repeating: sparkle)
                col = waterCol
            }
        }

        return col
    }

    // MARK: - Noise functions (exact port of Metal shader)

    private func hash(_ p: SIMD2<Float>) -> Float {
        let h = dot(p, SIMD2<Float>(127.1, 311.7))
        return fract(sin(h) * 43758.5453)
    }

    private func noise(_ p: SIMD2<Float>) -> Float {
        let i = floor(p)
        var f = p - i // fract
        f = f * f * (3.0 - 2.0 * f)
        let a = hash(i)
        let b = hash(i + SIMD2<Float>(1, 0))
        let c = hash(i + SIMD2<Float>(0, 1))
        let d = hash(i + SIMD2<Float>(1, 1))
        return mix(mix(a, b, t: f.x), mix(c, d, t: f.x), t: f.y)
    }

    private func fbm(_ p: SIMD2<Float>) -> Float {
        var p = p
        var v: Float = 0.0
        var a: Float = 0.5
        let shift = SIMD2<Float>(100.0, 100.0)
        for _ in 0..<5 {
            v += a * noise(p)
            p = p * 2.0 + shift
            a *= 0.5
        }
        return v
    }

    private func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(max((x - edge0) / (edge1 - edge0), 0.0), 1.0)
        return t * t * (3.0 - 2.0 * t)
    }

    private func fract(_ x: Float) -> Float {
        return x - floor(x)
    }

    private func mix(_ a: Float, _ b: Float, t: Float) -> Float {
        return a + (b - a) * t
    }

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: SIMD3<Float>) -> SIMD3<Float> {
        return a + (b - a) * t
    }
}
