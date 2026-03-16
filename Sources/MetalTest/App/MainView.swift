import SwiftUI
import Combine

final class RenderViewModel: ObservableObject {
    @Published var selectedScene: DemoSceneType = .scenery
    @Published var cpuFPS: Double = 0
    @Published var metalFPS: Double = 0
}

struct MainView: View {
    @StateObject private var viewModel = RenderViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Scene selector
            HStack {
                Text("Scene:")
                    .font(.headline)
                Picker("", selection: $viewModel.selectedScene) {
                    ForEach(DemoSceneType.allCases) { scene in
                        Text(scene.rawValue).tag(scene)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Side-by-side renderers
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Text("CPU (Core Graphics)")
                            .font(.system(.headline, design: .monospaced))
                        Spacer()
                        Text(String(format: "%.1f FPS", viewModel.cpuFPS))
                            .font(.system(.title2, design: .monospaced))
                            .foregroundColor(fpsColor(viewModel.cpuFPS))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.7))

                    CPURenderViewWrapper(viewModel: viewModel)
                }

                Rectangle()
                    .fill(Color.gray)
                    .frame(width: 2)

                VStack(spacing: 0) {
                    HStack {
                        Text("GPU (Metal)")
                            .font(.system(.headline, design: .monospaced))
                        Spacer()
                        Text(String(format: "%.1f FPS", viewModel.metalFPS))
                            .font(.system(.title2, design: .monospaced))
                            .foregroundColor(fpsColor(viewModel.metalFPS))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.7))

                    MetalRenderViewWrapper(viewModel: viewModel)
                }
            }
        }
    }

    private func fpsColor(_ fps: Double) -> Color {
        if fps >= 55 { return .green }
        if fps >= 30 { return .yellow }
        return .red
    }
}

// MARK: - NSViewRepresentable wrappers

struct CPURenderViewWrapper: NSViewRepresentable {
    @ObservedObject var viewModel: RenderViewModel

    func makeNSView(context: Context) -> CPURenderView {
        let view = CPURenderView(frame: .zero)
        view.scene = makeScene(viewModel.selectedScene)
        // Observe FPS
        context.coordinator.fpsCancellable = view.fpsCounter.$currentFPS
            .receive(on: RunLoop.main)
            .sink { [weak viewModel] fps in viewModel?.cpuFPS = fps }
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ nsView: CPURenderView, context: Context) {
        if context.coordinator.currentScene != viewModel.selectedScene {
            context.coordinator.currentScene = viewModel.selectedScene
            nsView.scene = makeScene(viewModel.selectedScene)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var fpsCancellable: AnyCancellable?
        var currentScene: DemoSceneType = .scenery
        weak var view: CPURenderView?
    }

    private func makeScene(_ type: DemoSceneType) -> SceneRenderable {
        switch type {
        case .scenery: return SceneryScene()
        case .scrollingText: return ScrollingTextScene()
        case .particles: return ParticlesScene()
        }
    }
}

struct MetalRenderViewWrapper: NSViewRepresentable {
    @ObservedObject var viewModel: RenderViewModel

    func makeNSView(context: Context) -> MetalRenderView {
        let view = MetalRenderView(frame: .zero)
        view.scene = makeScene(viewModel.selectedScene)
        context.coordinator.fpsCancellable = view.fpsCounter.$currentFPS
            .receive(on: RunLoop.main)
            .sink { [weak viewModel] fps in viewModel?.metalFPS = fps }
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ nsView: MetalRenderView, context: Context) {
        if context.coordinator.currentScene != viewModel.selectedScene {
            context.coordinator.currentScene = viewModel.selectedScene
            nsView.scene = makeScene(viewModel.selectedScene)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var fpsCancellable: AnyCancellable?
        var currentScene: DemoSceneType = .scenery
        weak var view: MetalRenderView?
    }

    private func makeScene(_ type: DemoSceneType) -> SceneRenderable {
        switch type {
        case .scenery: return SceneryScene()
        case .scrollingText: return ScrollingTextScene()
        case .particles: return ParticlesScene()
        }
    }
}
