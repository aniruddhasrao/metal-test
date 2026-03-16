import QuartzCore
import Combine

final class FPSCounter: ObservableObject {
    @Published var currentFPS: Double = 0

    private var timestamps: [CFTimeInterval] = []
    private let windowSize = 60

    func recordFrame() {
        let now = CACurrentMediaTime()
        timestamps.append(now)
        if timestamps.count > windowSize {
            timestamps.removeFirst(timestamps.count - windowSize)
        }
        guard timestamps.count >= 2,
              let first = timestamps.first,
              let last = timestamps.last else { return }
        let elapsed = last - first
        if elapsed > 0 {
            currentFPS = Double(timestamps.count - 1) / elapsed
        }
    }
}
