# Metal vs CPU Renderer

A macOS app that renders the same graphics side by side using Metal (GPU) and Core Graphics (CPU), with live FPS counters to visualize the performance difference.

## Demo Scenes

**3D Scenery** — Procedural landscape with sky gradient, animated sun, drifting clouds (FBM noise), layered mountains, trees, grass, and water with sparkles. Both renderers compute every pixel using the exact same algorithm (noise, FBM, smoothstep), making it a true apples-to-apples comparison. The GPU runs this massively in parallel; the CPU does it sequentially on one core.

**Scrolling Text** — Wall of colored monospaced text scrolling vertically. CPU draws each line per frame using CoreText. Metal scrolls a pre-rendered texture atlas.

**Particles** — 2,000 bouncing particles with gravity, wall collisions, and color cycling. CPU updates and draws each particle individually. Metal uses a compute shader for physics and instanced rendering for drawing.

## Requirements

- macOS 14+
- Xcode Command Line Tools (for `swift build` and `xcrun metal`)

## Build & Run

```
make run
```

This compiles the Metal shaders, builds the Swift executable, and launches the app.

Other targets:

```
make build     # compile only
make release   # release build
make clean     # remove build artifacts
```

## Architecture

```
Sources/
  MetalTest/
    main.swift                          # NSApplication entry point
    App/
      AppDelegate.swift                 # Window and menu setup
      MainView.swift                    # SwiftUI layout with scene picker
    Rendering/
      SceneProtocol.swift               # Protocol each scene implements
      CPURenderer/CPURenderView.swift   # NSView with CGContext bitmap rendering
      MetalRenderer/MetalRenderView.swift # NSView with CAMetalLayer
    Scenes/
      SceneryScene.swift                # Procedural landscape (per-pixel)
      ScrollingTextScene.swift          # Colored text wall
      ParticlesScene.swift              # Bouncing particles
    FPS/FPSCounter.swift                # Rolling-window FPS measurement
  ShaderTypes/                          # Shared C structs (Swift + Metal)
Shaders/
  SceneryShaders.metal                  # Procedural landscape fragment shader
  TextShaders.metal                     # Texture-scrolling fragment shader
  ParticleShaders.metal                 # Compute + instanced render shaders
```

The CPU renderer runs on a background thread to keep the UI responsive. Each scene implements both a `drawCPU(context:size:)` and `drawMetal(encoder:size:)` path. The scenery scene uses identical per-pixel math on both sides; the text and particle scenes use CGContext drawing primitives on the CPU side.
