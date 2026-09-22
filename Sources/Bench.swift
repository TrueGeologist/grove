import Darwin
import Foundation

#if GROVE_BENCH
@main
struct BenchMain {
    static func main() {
        testLayout()
        let path = CommandLine.arguments.dropFirst().first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
        benchScan(path)
    }

    static func testLayout() {
        let rect = CGRect(x: 0, y: 0, width: 800, height: 500)
        let sizes: [Int64] = [50, 25, 12, 8, 5, 0]
        let rects = TreemapLayout.rects(sizes: sizes, in: rect)
        var area: Double = 0
        for (index, tile) in rects.enumerated() where sizes[index] > 0 {
            precondition(tile.width > 0 && tile.height > 0, "missing tile")
            precondition(rect.contains(CGPoint(x: tile.midX, y: tile.midY)), "tile escaped")
            area += Double(tile.width * tile.height)
        }
        let expected = Double(rect.width * rect.height)
        let error = abs(area - expected) / expected
        precondition(error < 0.02, "area error \(error)")
        print("layout ok, coverage error \(String(format: "%.4f", error))")
    }

    static func benchScan(_ path: String) {
        var info = stat()
        guard stat(path, &info) == 0 else {
            fputs("missing \(path)\n", stderr)
            exit(1)
        }
        let store = TreeStore(rootPath: path, rootDevice: info.st_dev, displayName: (path as NSString).lastPathComponent)
        let scanner = DiskScanner(store: store)
        let done = DispatchSemaphore(value: 0)
        scanner.onFinished = { done.signal() }
        let started = Date()
        scanner.start()
        var last = 0
        while done.wait(timeout: .now() + 0.5) == .timedOut {
            let stats = store.stats()
            if stats.files != last {
                print("… \(stats.files) files, \(stats.allocBytes) bytes")
                last = stats.files
            }
        }
        let stats = store.stats()
        let elapsed = Date().timeIntervalSince(started)
        print("done \(stats.files) files, \(stats.allocBytes) bytes, unreadable \(stats.unreadable), \(String(format: "%.2f", elapsed))s")
    }
}
#endif
