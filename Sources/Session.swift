import AppKit
import Foundation
import QuickLookUI
import SwiftUI

@MainActor
final class GroveSession: ObservableObject {
    @Published var showWelcome = true
    @Published var showAbout = false
    @Published var snapshot = MapSnapshot.empty
    @Published var selectedID: Int64?
    @Published var filter = ""
    @Published var isScanning = false
    @Published var files = 0
    @Published var allocBytes: Int64 = 0
    @Published var unreadable = 0
    @Published var tip = ""
    @Published var statusLine = ""
    @Published var notice: String?
    @Published var volumeName = ""
    @Published var volumeTotal: Int64 = 0
    @Published var volumeFree: Int64 = 0
    @Published var hideAccessNote = false
    @Published var offerDiskAccess = false
    @Published private(set) var rootIsVolume = false
    @Published private(set) var rootPath: String?

    private var store: TreeStore?
    private var scanner: DiskScanner?
    private var currentID: Int64 = 1
    private var timer: Timer?
    private var startedAt = Date()
    private var finishedAt: Date?
    private var stoppedEarly = false
    private var searchTicket = 0
    private var scanGeneration = 0
    private let preview = PreviewBridge()
    private var noticeClear: DispatchWorkItem?

    private var didConsumeLaunchPath = false

    func openLaunchPathIfNeeded() {
        guard !didConsumeLaunchPath else { return }
        didConsumeLaunchPath = true
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--scan"), args.indices.contains(index + 1) else { return }
        let path = args[index + 1]
        guard FileManager.default.fileExists(atPath: path) else { return }
        start(URL(fileURLWithPath: path))
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = Copy.chooseFolder
        panel.message = Copy.tagline
        if panel.runModal() == .OK, let url = panel.url {
            start(url)
        }
    }

    func start(_ url: URL) {
        let path = url.resolvingSymlinksInPath().path
        rootIsVolume = Self.isVolumeRoot(path)
        var info = stat()
        guard stat(path, &info) == 0 else { return }
        scanner?.cancel()
        timer?.invalidate()
        scanGeneration += 1
        let generation = scanGeneration
        let name = FileManager.default.displayName(atPath: path)
        let tree = TreeStore(rootPath: path, rootDevice: info.st_dev, displayName: name.isEmpty ? url.lastPathComponent : name)
        store = tree
        rootPath = path
        currentID = 1
        selectedID = nil
        filter = ""
        files = 0
        allocBytes = 0
        unreadable = 0
        tip = path
        hideAccessNote = false
        offerDiskAccess = !DiskAccess.canReadProtectedFiles()
        notice = nil
        stoppedEarly = false
        startedAt = Date()
        finishedAt = nil
        isScanning = true
        showWelcome = false
        refreshVolume(for: path)
        remember(path)
        publish()

        let engine = DiskScanner(store: tree)
        scanner = engine
        engine.onFinished = { [weak self] in
            DispatchQueue.main.async {
                self?.finishScanning(generation: generation)
            }
        }
        engine.start()
        let tick = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer = tick
        RunLoop.main.add(tick, forMode: .common)
    }

    func rescan() {
        guard let rootPath else { return }
        start(URL(fileURLWithPath: rootPath))
    }

    func stop() {
        stoppedEarly = true
        scanner?.cancel()
        finishScanning(generation: scanGeneration)
    }

    func openWelcome() {
        showWelcome = true
    }

    func returnToMap() {
        guard rootPath != nil else { return }
        showWelcome = false
    }

    func goUp() {
        guard let store else { return }
        let parent = store.path(for: currentID).flatMap { _ in snapshot.crumbs.dropLast().last?.id }
        guard let parent, parent != currentID else { return }
        currentID = parent
        selectedID = nil
        publish()
    }

    func openCrumb(_ id: Int64) {
        currentID = id
        selectedID = nil
        publish()
    }

    func select(_ id: Int64) {
        guard snapshot.mapItems.contains(where: { contains($0, id: id) }) || snapshot.listItems.contains(where: { $0.id == id }) else {
            selectedID = id
            publish()
            return
        }
        selectedID = id
        publish()
    }

    func activate(_ id: Int64) {
        if store?.nodeIsDirectory(id) == true {
            currentID = id
            selectedID = nil
            publish()
        } else {
            selectedID = id
            publish()
            quickLook()
        }
    }

    func reveal() {
        guard let path = selectedPath() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func quickLook() {
        guard let path = selectedPath(), store?.nodeIsDirectory(selectedID ?? -1) != true else {
            if let path = selectedPath() {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            return
        }
        preview.show(URL(fileURLWithPath: path))
    }

    func copySelectedPath() {
        guard let path = selectedPath() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        flash(Copy.pathCopied)
    }

    func trash() {
        guard let id = selectedID, let store, let path = store.path(for: id) else { return }
        if store.protected(id: id) {
            let alert = NSAlert()
            alert.messageText = Copy.protectedTitle
            alert.informativeText = Copy.protectedBody
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        let size = snapshot.selection?.allocSize ?? 0
        let name = snapshot.selection?.name ?? (path as NSString).lastPathComponent
        let alert = NSAlert()
        alert.messageText = Copy.trashTitle
        alert.informativeText = "\(name) — \(Format.bytes(size)). \(Copy.freedNote) \(Format.bytes(size))."
        alert.alertStyle = .warning
        alert.addButton(withTitle: Copy.trash)
        alert.addButton(withTitle: Copy.cancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            let removedCurrent = isCurrentInside(id)
            _ = store.remove(id: id)
            if removedCurrent { goUp() }
            selectedID = nil
            refreshVolume(for: self.rootPath ?? path)
            publish()
        } catch {
            let failure = NSAlert()
            failure.messageText = Copy.trashFailed
            failure.informativeText = error.localizedDescription
            failure.alertStyle = .warning
            failure.addButton(withTitle: "OK")
            failure.runModal()
        }
    }

    func openPrivacySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }

    func scheduleFilterRefresh() {
        searchTicket += 1
        let ticket = searchTicket
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, ticket == self.searchTicket else { return }
            self.publish()
        }
    }

    private func tick() {
        guard let store else { return }
        let stats = store.stats()
        files = stats.files
        allocBytes = stats.allocBytes
        unreadable = stats.unreadable
        tip = stats.tip
        statusLine = makeStatus(final: false)
        if filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            snapshot = store.makeSnapshot(currentID: currentID, selectedID: selectedID, query: "")
        } else if Int(Date().timeIntervalSince(startedAt) * 10) % 8 == 0 {
            snapshot = store.makeSnapshot(currentID: currentID, selectedID: selectedID, query: filter)
        }
    }

    private func finishScanning(generation: Int) {
        guard generation == scanGeneration, isScanning else { return }
        isScanning = false
        finishedAt = Date()
        timer?.invalidate()
        timer = nil
        statusLine = makeStatus(final: true)
        publish()
    }

    func relocalize() {
        guard store != nil else { return }
        publish()
    }

    private func publish() {
        guard let store else { return }
        let stats = store.stats()
        files = stats.files
        allocBytes = stats.allocBytes
        unreadable = stats.unreadable
        tip = stats.tip
        snapshot = store.makeSnapshot(currentID: currentID, selectedID: selectedID, query: filter)
        statusLine = makeStatus(final: !isScanning)
    }

    private func makeStatus(final: Bool) -> String {
        let sizeText = diskUsedText ?? Format.bytes(allocBytes)
        let amount = "\(Format.files(files)) · \(sizeText)"
        if !final {
            let elapsed = Date().timeIntervalSince(startedAt)
            let rate = elapsed > 0.4 ? Format.rate(Double(files) / elapsed) : ""
            let pieces = [Copy.scanning, amount, rate].filter { !$0.isEmpty }
            return pieces.joined(separator: " · ")
        }
        let elapsed = (finishedAt ?? Date()).timeIntervalSince(startedAt)
        let title = stoppedEarly ? Copy.stopped : Copy.done
        return "\(title) · \(amount) · \(Format.duration(elapsed))"
    }

    /// Same figure as System Settings: capacity minus space available for important use.
    private var diskUsedText: String? {
        guard rootIsVolume, volumeTotal > 0, volumeFree > 0 else { return nil }
        let used = max(0, volumeTotal - volumeFree)
        return "\(Copy.used) \(Format.bytes(used))"
    }

    private static func isVolumeRoot(_ path: String) -> Bool {
        if path == "/" { return true }
        let mounts = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
        return mounts.contains { $0.resolvingSymlinksInPath().path == path }
    }

    private func selectedPath() -> String? {
        guard let id = selectedID else { return nil }
        return store?.path(for: id)
    }

    private func isCurrentInside(_ id: Int64) -> Bool {
        if currentID == id { return true }
        return snapshot.crumbs.contains { $0.id == id }
    }

    private func contains(_ item: MapItem, id: Int64) -> Bool {
        if item.id == id { return true }
        return item.children.contains { contains($0, id: id) }
    }

    private func flash(_ text: String) {
        notice = text
        noticeClear?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.notice = nil }
        noticeClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    private func refreshVolume(for path: String) {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeLocalizedNameKey,
            .volumeNameKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return }
        volumeTotal = Int64(values.volumeTotalCapacity ?? 0)
        let important = values.volumeAvailableCapacityForImportantUsage ?? 0
        let available = Int64(values.volumeAvailableCapacity ?? 0)
        let reportedFree = important > 0 ? important : available
        volumeFree = volumeTotal > 0 ? min(reportedFree, volumeTotal) : reportedFree
        volumeName = values.volumeLocalizedName ?? values.volumeName ?? ""
    }

    private func remember(_ path: String) {
        let key = "grove.recents"
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(6)), forKey: key)
    }

    static func recentPaths() -> [String] {
        let paths = UserDefaults.standard.stringArray(forKey: "grove.recents") ?? []
        return paths.filter { FileManager.default.fileExists(atPath: $0) }
    }

    static func volumes() -> [VolumeChoice] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeLocalizedNameKey,
            .volumeIsInternalKey,
        ], options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeLocalizedNameKey,
            ])
            let name = values?.volumeLocalizedName ?? url.lastPathComponent
            guard !name.isEmpty else { return nil }
            return VolumeChoice(
                name: name,
                path: url.path,
                total: Int64(values?.volumeTotalCapacity ?? 0),
                free: values?.volumeAvailableCapacityForImportantUsage ?? 0
            )
        }
    }
}

struct VolumeChoice: Identifiable {
    var id: String { path }
    var name: String
    var path: String
    var total: Int64
    var free: Int64
}

enum DiskAccess {
    /// Mail, Messages and Safari live behind Full Disk Access. TCC.db is the same gate.
    static func canReadProtectedFiles() -> Bool {
        let probe = "/Library/Application Support/com.apple.TCC/TCC.db"
        let fd = open(probe, O_RDONLY)
        if fd >= 0 {
            close(fd)
            return true
        }
        return false
    }
}

final class PreviewBridge: NSObject, QLPreviewPanelDataSource {
    private var url: URL?

    func show(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem {
        (url ?? URL(fileURLWithPath: "/")) as NSURL
    }
}
