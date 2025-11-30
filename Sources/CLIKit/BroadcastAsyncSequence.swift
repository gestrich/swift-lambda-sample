import Foundation

/// An AsyncSequence that broadcasts elements to multiple concurrent subscribers.
/// Each subscriber receives elements from the point they subscribe forward.
///
/// Usage:
/// ```swift
/// let broadcast = BroadcastAsyncSequence<String>()
///
/// // Subscriber 1
/// Task {
///     for await element in broadcast {
///         print("Subscriber 1: \(element)")
///     }
/// }
///
/// // Subscriber 2
/// Task {
///     for await element in broadcast {
///         print("Subscriber 2: \(element)")
///     }
/// }
///
/// // Producer
/// broadcast.yield("Hello")
/// broadcast.yield("World")
/// broadcast.finish()
/// ```
@MainActor
public final class BroadcastAsyncSequence<Element: Sendable>: AsyncSequence, Sendable {
    public typealias AsyncIterator = Iterator
    public typealias Failure = Never

    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    public init() {}

    /// Broadcast an element to all current subscribers
    public func yield(_ element: Element) {
        for continuation in continuations.values {
            continuation.yield(element)
        }
    }

    /// Signal completion to all subscribers
    public func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    public nonisolated func makeAsyncIterator() -> Iterator {
        Iterator(parent: self)
    }

    private func register(id: UUID, continuation: AsyncStream<Element>.Continuation) {
        continuations[id] = continuation
    }

    private func unregister(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    public struct Iterator: AsyncIteratorProtocol {
        private let id = UUID()
        private var streamIterator: AsyncStream<Element>.Iterator
        private let parent: BroadcastAsyncSequence

        init(parent: BroadcastAsyncSequence) {
            self.parent = parent

            var capturedContinuation: AsyncStream<Element>.Continuation?
            let stream = AsyncStream<Element> { continuation in
                capturedContinuation = continuation
            }

            // Register with parent on main actor
            if let continuation = capturedContinuation {
                let id = self.id
                Task { @MainActor in
                    parent.register(id: id, continuation: continuation)
                }

                continuation.onTermination = { @Sendable _ in
                    Task { @MainActor in
                        parent.unregister(id: id)
                    }
                }
            }

            self.streamIterator = stream.makeAsyncIterator()
        }

        public mutating func next() async -> Element? {
            await streamIterator.next()
        }
    }
}
