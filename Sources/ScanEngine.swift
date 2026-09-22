import Darwin
import Foundation

final class ScanNode {
    let id: Int64
    let name: String
    let path: String
    let isDirectory: Bool
    let category: FileCategory
    weak var parent: ScanNode?
    var allocSize: Int64 = 0
    var logicalSize: Int64 = 0
    var fileCount: Int = 0
    var children: [ScanNode] = []
    var unreadable = false
    var otherVolume = false
    var removed = false

    init(id: Int64, name: String, path: String, isDirectory: Bool, category: FileCategory) {
        self.id = id
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.category = category
    }
}

struct MapItem: Identifiable {
    enum Kind {
        case node
        case aggregate
    }

    var id: Int64
    var name: String
    var path: String
    var allocSize: Int64
    var logicalSize: Int64
    var isDirectory: Bool
    var category: FileCategory
    var fileCount: Int
    var children: [MapItem]
    var kind: Kind
    var location: String

    var isAggregate: Bool { kind == .aggregate }
}

struct Crumb: Identifiable {
    var id: Int64
    var name: String
}

struct SelectionInfo: Identifiable {
    var id: Int64
    var name: String
    var path: String
    var allocSize: Int64
    var logicalSize: Int64
    var isDirectory: Bool
    var category: FileCategory
    var fileCount: Int
    var share: Double
    var protected: Bool
}

struct MapSnapshot {
    var currentID: Int64 = 0
    var currentName: String = ""
    var currentPath: String = ""
    var currentSize: Int64 = 0
    var crumbs: [Crumb] = []
    var mapItems: [MapItem] = []
    var listItems: [MapItem] = []
    var selection: SelectionInfo?
    var filtering: Bool = false

    static let empty = MapSnapshot()
}

struct ScanStats {
    var files: Int = 0
    var allocBytes: Int64 = 0
    var unreadable: Int = 0
    var tip: String = ""
}

/// Owns the scanned tree. Every mutation and every read goes through `lock`.
final class TreeStore: @unchecked Sendable {
    let lock = NSLock()
    private(set) var root: ScanNode?
    private var index: [Int64: ScanNode] = [:]
    private var nextID: Int64 = 1
    private var unreadable = 0
    private var tip = ""
    private var seenDirs: Set<DirKey> = []
    let rootDevice: dev_t
    let rootPath: String

    init(rootPath: String, rootDevice: dev_t, displayName: String) {
        self.rootPath = rootPath
        self.rootDevice = rootDevice
        _ = claimDirectory(at: rootPath)
        let node = ScanNode(
            id: 1,
            name: displayName,
            path: rootPath,
            isDirectory: true,
            category: .folder
        )
        nextID = 2
        root = node
        index[node.id] = node
    }

    func stats() -> ScanStats {
        lock.lock()
        defer { lock.unlock() }
        return ScanStats(
            files: root?.fileCount ?? 0,
            allocBytes: root?.allocSize ?? 0,
            unreadable: unreadable,
            tip: tip
        )
    }

    func nodeIsDirectory(_ id: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return index[id]?.isDirectory ?? false
    }

    func makeSnapshot(currentID: Int64, selectedID: Int64?, query: String) -> MapSnapshot {
        lock.lock()
        defer { lock.unlock() }
        guard let root else { return .empty }
        let current = index[currentID] ?? root
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var snapshot = MapSnapshot(
            currentID: current.id,
            currentName: current.name,
            currentPath: current.path,
            currentSize: current.allocSize,
            crumbs: crumbs(of: current),
            filtering: !trimmed.isEmpty
        )
        if trimmed.isEmpty {
            snapshot.mapItems = mapChildren(of: current, depth: 0)
            snapshot.listItems = Array(topLargest(current.children, 400).map { listItem($0) })
        } else {
            let found = search(from: current, query: trimmed, limit: 240)
            snapshot.mapItems = found.map { listItem($0) }
            snapshot.listItems = snapshot.mapItems
        }
        if let selectedID, let node = index[selectedID] {
            snapshot.selection = selection(node, relativeTo: current)
        }
        return snapshot
    }

    func remove(id: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let node = index[id], let parent = node.parent else { return false }
        subtract(alloc: node.allocSize, logical: node.logicalSize, files: node.fileCount, from: parent)
        parent.children.removeAll { $0.id == id }
        detach(node)
        return true
    }

    func path(for id: Int64) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return index[id]?.path
    }

    func protected(id: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let path = index[id]?.path else { return true }
        return ProtectedPath.contains(path)
    }

    func adoptListing(_ listing: ListedDirectory, into parentID: Int64) -> [ScanNode] {
        lock.lock()
        defer { lock.unlock() }
        guard let parent = index[parentID], !parent.removed else { return [] }
        if listing.unreadable {
            parent.unreadable = true
            unreadable += 1
        }
        if listing.crossesVolume {
            parent.otherVolume = true
            return []
        }
        tip = parent.path
        if listing.directoryAlloc > 0 {
            add(alloc: listing.directoryAlloc, logical: 0, files: 0, to: parent)
        }

        var directories: [ScanNode] = []
        directories.reserveCapacity(listing.entries.count / 4)
        parent.children.reserveCapacity(parent.children.count + listing.entries.count)

        var fileAlloc: Int64 = 0
        var fileLogical: Int64 = 0
        var fileCount = 0

        for entry in listing.entries {
            let childPath = parent.path == "/" ? "/\(entry.name)" : parent.path + "/" + entry.name
            let directory = entry.isDirectory && !entry.isSymlink
            if directory, !claimDirectory(at: childPath) {
                continue
            }
            let node = ScanNode(
                id: nextID,
                name: entry.name,
                path: childPath,
                isDirectory: directory,
                category: FileCategory.classify(name: entry.name, isDirectory: directory)
            )
            nextID += 1
            node.parent = parent
            index[node.id] = node
            parent.children.append(node)
            if directory {
                directories.append(node)
            } else {
                node.allocSize = entry.allocSize
                node.logicalSize = entry.logicalSize > 0 ? entry.logicalSize : entry.allocSize
                fileAlloc += entry.allocSize
                fileLogical += node.logicalSize
                fileCount += 1
            }
        }
        if fileCount > 0 {
            add(alloc: fileAlloc, logical: fileLogical, files: fileCount, to: parent)
        }
        return directories
    }

    /// Firmlinks such as `/Users` and `/System/Volumes/Data/Users` are the same directory.
    /// Counting both would report about twice the space the disk actually uses.
    private func claimDirectory(at path: String) -> Bool {
        var info = stat()
        guard path.withCString({ lstat($0, &info) }) == 0 else { return true }
        return seenDirs.insert(DirKey(dev: UInt64(bitPattern: Int64(info.st_dev)), ino: info.st_ino)).inserted
    }

    private func add(alloc: Int64, logical: Int64, files: Int, to node: ScanNode) {
        var current: ScanNode? = node
        while let cursor = current, !cursor.removed {
            cursor.allocSize += alloc
            cursor.logicalSize += logical
            cursor.fileCount += files
            current = cursor.parent
        }
    }

    private func subtract(alloc: Int64, logical: Int64, files: Int, from node: ScanNode) {
        var current: ScanNode? = node
        while let cursor = current {
            cursor.allocSize = max(0, cursor.allocSize - alloc)
            cursor.logicalSize = max(0, cursor.logicalSize - logical)
            cursor.fileCount = max(0, cursor.fileCount - files)
            current = cursor.parent
        }
    }

    private func detach(_ node: ScanNode) {
        var stack = [node]
        while let current = stack.popLast() {
            current.removed = true
            current.parent = nil
            index[current.id] = nil
            stack.append(contentsOf: current.children)
            current.children = []
        }
    }

    private func crumbs(of node: ScanNode) -> [Crumb] {
        var chain: [Crumb] = []
        var current: ScanNode? = node
        while let cursor = current {
            chain.append(Crumb(id: cursor.id, name: cursor.name))
            current = cursor.parent
        }
        return chain.reversed()
    }

    private func mapChildren(of node: ScanNode, depth: Int) -> [MapItem] {
        let limit = depth == 0 ? 320 : (depth == 1 ? 22 : 8)
        let top = topLargest(node.children, limit)
        var items: [MapItem] = []
        items.reserveCapacity(top.count + 1)
        var expanded = 0
        let expansionBudget = depth == 0 ? 28 : (depth == 1 ? 6 : 0)
        for child in top {
            var item = listItem(child)
            if child.isDirectory, expanded < expansionBudget, child.allocSize > 0, depth < 2 {
                item.children = mapChildren(of: child, depth: depth + 1)
                expanded += 1
            }
            items.append(item)
        }
        let shown = top.reduce(Int64(0)) { $0 + $1.allocSize }
        let hiddenCount = node.children.count - top.count
        let rest = node.allocSize - shown
        if depth == 0, hiddenCount > 0, rest > max(node.allocSize / 80, 128 * 1024) {
            let hiddenFiles = max(0, node.fileCount - top.reduce(0) { $0 + $1.fileCount })
            items.append(
                MapItem(
                    id: aggregateID(parent: node.id, depth: depth),
                    name: Copy.remainder,
                    path: node.path,
                    allocSize: rest,
                    logicalSize: rest,
                    isDirectory: true,
                    category: .folder,
                    fileCount: hiddenFiles,
                    children: [],
                    kind: .aggregate,
                    location: node.path
                )
            )
        }
        return items
    }

    private func listItem(_ node: ScanNode) -> MapItem {
        MapItem(
            id: node.id,
            name: node.name,
            path: node.path,
            allocSize: node.allocSize,
            logicalSize: node.logicalSize,
            isDirectory: node.isDirectory,
            category: node.category,
            fileCount: node.fileCount,
            children: [],
            kind: .node,
            location: (node.path as NSString).deletingLastPathComponent
        )
    }

    private func selection(_ node: ScanNode, relativeTo current: ScanNode) -> SelectionInfo {
        SelectionInfo(
            id: node.id,
            name: node.name,
            path: node.path,
            allocSize: node.allocSize,
            logicalSize: node.logicalSize,
            isDirectory: node.isDirectory,
            category: node.category,
            fileCount: node.fileCount,
            share: current.allocSize > 0 ? Double(node.allocSize) / Double(current.allocSize) : 0,
            protected: ProtectedPath.contains(node.path)
        )
    }

    private func search(from root: ScanNode, query: String, limit: Int) -> [ScanNode] {
        var best: [ScanNode] = []
        func consider(_ node: ScanNode) {
            if best.count < limit {
                best.append(node)
                if best.count == limit { heapify() }
                return
            }
            if node.allocSize > best[0].allocSize {
                best[0] = node
                siftDown(0)
            }
        }
        func heapify() {
            var index = best.count / 2
            while index >= 0 {
                siftDown(index)
                index -= 1
            }
        }
        func siftDown(_ start: Int) {
            var index = start
            while true {
                let left = index * 2 + 1
                let right = left + 1
                var smallest = index
                if left < best.count, best[left].allocSize < best[smallest].allocSize { smallest = left }
                if right < best.count, best[right].allocSize < best[smallest].allocSize { smallest = right }
                if smallest == index { break }
                best.swapAt(index, smallest)
                index = smallest
            }
        }
        func visit(_ node: ScanNode, isOrigin: Bool) {
            if node.removed { return }
            if !isOrigin, node.name.range(of: query, options: .caseInsensitive) != nil {
                consider(node)
                if node.isDirectory { return }
            }
            if node.isDirectory {
                for child in node.children { visit(child, isOrigin: false) }
            }
        }
        visit(root, isOrigin: true)
        return best.sorted { $0.allocSize > $1.allocSize }
    }

    private func topLargest(_ nodes: [ScanNode], _ limit: Int) -> [ScanNode] {
        let useful = nodes.filter { $0.allocSize > 0 && !$0.removed }
        if useful.count <= limit {
            return useful.sorted { $0.allocSize > $1.allocSize }
        }
        var best: [ScanNode] = []
        best.reserveCapacity(limit)
        func siftDown(_ start: Int) {
            var index = start
            while true {
                let left = index * 2 + 1
                let right = left + 1
                var smallest = index
                if left < best.count, best[left].allocSize < best[smallest].allocSize { smallest = left }
                if right < best.count, best[right].allocSize < best[smallest].allocSize { smallest = right }
                if smallest == index { break }
                best.swapAt(index, smallest)
                index = smallest
            }
        }
        for node in useful {
            if best.count < limit {
                best.append(node)
                if best.count == limit {
                    var index = best.count / 2
                    while index >= 0 {
                        siftDown(index)
                        index -= 1
                    }
                }
            } else if node.allocSize > best[0].allocSize {
                best[0] = node
                siftDown(0)
            }
        }
        return best.sorted { $0.allocSize > $1.allocSize }
    }

    private func aggregateID(parent: Int64, depth: Int) -> Int64 {
        -((parent &* 8) &+ Int64(depth) &+ 1)
    }
}

private struct DirKey: Hashable {
    var dev: UInt64
    var ino: ino_t
}

enum ProtectedPath {
    static func contains(_ path: String) -> Bool {
        let home = NSHomeDirectory()
        let banned: Set<String> = [
            "/", "/System", "/System/Volumes", "/usr", "/bin", "/sbin", "/opt",
            "/Users", "/Applications", "/Library", "/private", "/Volumes", home,
        ]
        return banned.contains(path)
    }
}

final class WorkPump {
    private let condition = NSCondition()
    private var items: [ScanNode] = []
    private var head = 0
    private var active = 0
    private var stopped = false

    func push(_ nodes: [ScanNode]) {
        if nodes.isEmpty { return }
        condition.lock()
        if !stopped {
            items.append(contentsOf: nodes)
            condition.broadcast()
        }
        condition.unlock()
    }

    func next() -> ScanNode? {
        condition.lock()
        defer { condition.unlock() }
        while readableEmpty && !stopped {
            if active == 0 {
                stopped = true
                condition.broadcast()
                return nil
            }
            condition.wait()
        }
        if readableEmpty || stopped { return nil }
        let node = items[head]
        head += 1
        if head > 2048, head * 2 > items.count {
            items.removeFirst(head)
            head = 0
        }
        active += 1
        return node
    }

    func finishJob() -> Bool {
        condition.lock()
        active -= 1
        let complete = items.count == head && active == 0 && !stopped
        if items.count == head && active == 0 {
            stopped = true
            condition.broadcast()
        }
        condition.unlock()
        return complete
    }

    func stop() {
        condition.lock()
        stopped = true
        items.removeAll()
        head = 0
        condition.broadcast()
        condition.unlock()
    }

    private var readableEmpty: Bool { head >= items.count }
}

final class DiskScanner {
    private let store: TreeStore
    private let pump = WorkPump()
    private let workers: Int
    private var cancelled = false
    private let cancelLock = NSLock()
    var onFinished: (@Sendable () -> Void)?

    init(store: TreeStore) {
        self.store = store
        let cores = ProcessInfo.processInfo.activeProcessorCount
        workers = min(8, max(4, cores))
    }

    func start() {
        guard let root = store.root else { return }
        pump.push([root])
        for _ in 0..<workers {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.loop()
            }
        }
    }

    func cancel() {
        cancelLock.lock()
        cancelled = true
        cancelLock.unlock()
        pump.stop()
    }

    private func isCancelled() -> Bool {
        cancelLock.lock()
        defer { cancelLock.unlock() }
        return cancelled
    }

    private func loop() {
        while let node = pump.next() {
            autoreleasepool {
                scan(node)
            }
            if pump.finishJob() {
                onFinished?()
            }
        }
    }

    private func scan(_ node: ScanNode) {
        if isCancelled() { return }
        store.lock.lock()
        let removed = node.removed
        let path = node.path
        let id = node.id
        store.lock.unlock()
        if removed { return }

        let listing = DirectoryListing.list(path, rootDevice: store.rootDevice)
        if isCancelled() { return }
        let directories = store.adoptListing(listing, into: id)
        if !directories.isEmpty, !isCancelled() {
            pump.push(directories)
        }
    }
}
