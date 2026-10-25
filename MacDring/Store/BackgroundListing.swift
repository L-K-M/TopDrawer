import Foundation

/// Main-thread-owned listing work. Cancellation discards replies; it cannot interrupt filesystem calls.
final class BackgroundListing<Value> {
    private var generation = UUID()

    func load(_ read: @escaping () -> Value, completion: @escaping (Value) -> Void) {
        cancel()
        let generation = generation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let value = read()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation else { return }
                completion(value)
            }
        }
    }

    func cancel() {
        generation = UUID()
    }
}
