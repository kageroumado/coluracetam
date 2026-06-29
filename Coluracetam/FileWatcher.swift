import Foundation

/// Watches a file for on-disk changes and yields an event on each one.
///
/// Editors typically save atomically (write a temp file, then rename over the
/// original), which swaps the inode out from under a plain descriptor watch — so
/// on delete/rename the watch is torn down and re-armed against the path.
///
/// Consume from a `.task(id:)`; cancelling the task (or the stream terminating)
/// stops watching and closes the descriptor.
enum FileWatcher {
    /// An async sequence that emits each time `url` changes on disk.
    ///
    /// Rapid bursts (e.g. a multi-write save) are coalesced to a single event.
    static func changes(for url: URL) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let watch = Watch(url: url, continuation: continuation)
            watch.queue.async { watch.arm() }
            continuation.onTermination = { _ in
                watch.queue.async { watch.cancel() }
            }
        }
    }
}

/// Mutable watch state, confined to its serial `queue` (hence `@unchecked`).
///
/// `nonisolated` because the app module defaults to `@MainActor` isolation, but
/// this type lives entirely on its own background `queue` — its methods are
/// invoked from `queue.async` and the stream's `onTermination`, never the main
/// actor. Without this they'd be inferred main-actor-isolated and every call
/// site would be a concurrency violation.
private final nonisolated class Watch: @unchecked Sendable {
    let url: URL
    let queue = DispatchQueue(label: "glass.kagerou.coluracetam.filewatcher")
    private let continuation: AsyncStream<Void>.Continuation
    private var source: (any DispatchSourceFileSystemObject)?
    private var cancelled = false

    init(url: URL, continuation: AsyncStream<Void>.Continuation) {
        self.url = url
        self.continuation = continuation
    }

    func arm() {
        guard !cancelled else { return }

        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            // The path may be momentarily absent mid atomic-replace; retry.
            queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.arm() }
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename, .revoke, .link],
            queue: queue,
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            self.continuation.yield(())
            if !flags.isDisjoint(with: [.delete, .rename, .revoke]) {
                // The inode we were watching is gone; re-arm against the path.
                source.cancel()
                self.source = nil
                self.queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.arm() }
            }
        }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
    }

    func cancel() {
        cancelled = true
        source?.cancel()
        source = nil
        continuation.finish()
    }
}
