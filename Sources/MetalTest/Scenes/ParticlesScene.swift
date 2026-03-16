import AppKit
import Metal
import ShaderTypes

final class ParticlesScene: SceneRenderable {
    let sceneType = DemoSceneType.particles
    let vertexFunctionName = "particle_vertex"
    let fragmentFunctionName = "particle_fragment"
    let computeFunctionName: String? = "particle_update"

    private var time: Double = 0
    private let particleCount = 2000
    private var particles: [ParticleData] = []
    private var particleBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?
    private var countBuffer: MTLBuffer?
    private var computePipeline: MTLComputePipelineState?
    private var currentSize: CGSize = .zero

    init() {
        resetParticles(size: CGSize(width: 600, height: 600))
    }

    private func resetParticles(size: CGSize) {
        particles = (0..<particleCount).map { i in
            let phase = Double(i) / Double(particleCount) * .pi * 2
            return ParticleData(
                position: SIMD2<Float>(
                    Float.random(in: 0...Float(size.width)),
                    Float.random(in: 0...Float(size.height))
                ),
                velocity: SIMD2<Float>(
                    Float(cos(phase)) * Float.random(in: 50...200),
                    Float(sin(phase)) * Float.random(in: -300 ... -50)
                ),
                color: SIMD4<Float>(
                    Float(0.5 + 0.5 * sin(phase)),
                    Float(0.5 + 0.5 * sin(phase + 2.094)),
                    Float(0.5 + 0.5 * sin(phase + 4.189)),
                    0.85
                ),
                size: Float.random(in: 3...10),
                _padding: (0, 0, 0)
            )
        }
    }

    func update(deltaTime: Double, time: Double, size: CGSize) {
        self.time = time
        self.currentSize = size

        // CPU particle update
        let dt = Float(min(deltaTime, 1.0 / 30.0))
        for i in 0..<particles.count {
            particles[i].velocity.y += 150.0 * dt
            particles[i].position += particles[i].velocity * dt

            // Bounce
            if particles[i].position.x < 0 {
                particles[i].position.x = 0
                particles[i].velocity.x *= -0.8
            }
            if particles[i].position.x > Float(size.width) {
                particles[i].position.x = Float(size.width)
                particles[i].velocity.x *= -0.8
            }
            if particles[i].position.y < 0 {
                particles[i].position.y = 0
                particles[i].velocity.y *= -0.8
            }
            if particles[i].position.y > Float(size.height) {
                particles[i].position.y = Float(size.height)
                particles[i].velocity.y *= -0.8
                let hash = pseudoRandom(seed: Double(i) + time)
                if hash > 0.7 {
                    particles[i].velocity.y -= 200.0 * Float(hash)
                    particles[i].velocity.x += Float(hash - 0.5) * 100.0
                }
            }

            // Color cycling
            let phase = Float(time * 0.5) + Float(i) * 0.01
            particles[i].color = SIMD4<Float>(
                0.5 + 0.5 * sin(phase),
                0.5 + 0.5 * sin(phase + 2.094),
                0.5 + 0.5 * sin(phase + 4.189),
                0.85
            )
        }
    }

    private func pseudoRandom(seed: Double) -> Double {
        var x = seed * 127.1
        x = sin(x) * 43758.5453
        return x - floor(x)
    }

    // MARK: - Metal

    func setupMetal(device: MTLDevice, library: MTLLibrary) {
        let bufferSize = MemoryLayout<ParticleData>.stride * particleCount
        particleBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
        uniformBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.stride, options: .storageModeShared)
        countBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared)

        if let countBuffer {
            var count = UInt32(particleCount)
            memcpy(countBuffer.contents(), &count, MemoryLayout<UInt32>.stride)
        }

        // Upload initial particle data
        if let particleBuffer {
            memcpy(particleBuffer.contents(), &particles, MemoryLayout<ParticleData>.stride * particleCount)
        }

        if let fn = library.makeFunction(name: "particle_update") {
            computePipeline = try? device.makeComputePipelineState(function: fn)
        }
    }

    func computeMetal(commandBuffer: MTLCommandBuffer, size: CGSize) {
        guard let computePipeline,
              let computeEncoder = commandBuffer.makeComputeCommandEncoder(),
              let particleBuffer, let uniformBuffer, let countBuffer else { return }

        var uniforms = Uniforms(
            time: Float(time),
            scrollOffset: 0,
            resolution: SIMD2<Float>(Float(size.width), Float(size.height))
        )
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)

        computeEncoder.setComputePipelineState(computePipeline)
        computeEncoder.setBuffer(particleBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(uniformBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(countBuffer, offset: 0, index: 2)

        let threadGroupSize = min(computePipeline.maxTotalThreadsPerThreadgroup, particleCount)
        let threadGroups = (particleCount + threadGroupSize - 1) / threadGroupSize
        computeEncoder.dispatchThreadgroups(
            MTLSize(width: threadGroups, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadGroupSize, height: 1, depth: 1)
        )
        computeEncoder.endEncoding()
    }

    func drawMetal(encoder: MTLRenderCommandEncoder, size: CGSize) {
        guard let particleBuffer, let uniformBuffer else { return }

        var uniforms = Uniforms(
            time: Float(time),
            scrollOffset: 0,
            resolution: SIMD2<Float>(Float(size.width), Float(size.height))
        )
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)

        encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: particleCount)
    }

    // MARK: - CPU Rendering

    func drawCPU(context: CGContext, size: CGSize) {
        // Dark background
        context.setFillColor(NSColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))

        for p in particles {
            let color = NSColor(
                red: CGFloat(p.color.x),
                green: CGFloat(p.color.y),
                blue: CGFloat(p.color.z),
                alpha: CGFloat(p.color.w)
            )
            context.setFillColor(color.cgColor)
            let s = CGFloat(p.size)
            context.fillEllipse(in: CGRect(
                x: CGFloat(p.position.x) - s/2,
                y: CGFloat(size.height - CGFloat(p.position.y)) - s/2,
                width: s, height: s
            ))
        }
    }
}
