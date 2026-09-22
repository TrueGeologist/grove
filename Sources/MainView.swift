import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: GroveSession

    var body: some View {
        Group {
            if session.showWelcome {
                WelcomeView()
            } else {
                BrowserView()
            }
        }
        .frame(minWidth: 860, minHeight: 540)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $session.showAbout) {
            AboutView()
        }
    }
}

struct BrowserView: View {
    @EnvironmentObject private var session: GroveSession
    @Environment(\.colorScheme) private var scheme
    @State private var topInset: CGFloat = 0
    @State private var bottomInset: CGFloat = 0

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 420)
        } detail: {
            detail
        }
        .toolbar { toolbar }
        .toolbarBackground(.visible, for: .windowToolbar)
        .searchable(text: $session.filter, placement: .toolbar, prompt: Copy.filterPrompt)
        .onChange(of: session.filter) { _, _ in
            session.scheduleFilterRefresh()
        }
        .onDeleteCommand { session.trash() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(GroveColor.canvas(scheme))
    }

    private var sidebar: some View {
        let items = session.snapshot.listItems
        let largest = items.first?.allocSize ?? 1
        return BoundedColumn {
            volumeHeader
            HStack {
                Text(session.snapshot.filtering ? Copy.matches : Copy.largest)
                    .font(.headline)
                Spacer()
                Text(Format.items(items.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)
            List(items, selection: sidebarSelection(items: items)) { item in
                SidebarRow(item: item, maxSize: largest)
                    .tag(item.id)
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        session.activate(item.id)
                    })
                    .contextMenu {
                        Button(Copy.reveal) {
                            session.select(item.id)
                            session.reveal()
                        }
                        Button(Copy.quickLook) {
                            session.select(item.id)
                            session.quickLook()
                        }
                        Button(Copy.copyPath) {
                            session.select(item.id)
                            session.copySelectedPath()
                        }
                        Divider()
                        Button(Copy.trash, role: .destructive) {
                            session.select(item.id)
                            session.trash()
                        }
                    }
            }
            .listStyle(.inset)
            .fitsRemainingHeight()
        }
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .clipped()
    }

    private func sidebarSelection(items: [MapItem]) -> Binding<Int64?> {
        Binding(
            get: {
                guard let selected = session.selectedID, items.contains(where: { $0.id == selected }) else { return nil }
                return selected
            },
            set: { newValue in
                if let newValue {
                    session.select(newValue)
                }
            }
        )
    }

    private var volumeHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.volumeName.isEmpty ? session.snapshot.currentName : session.volumeName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if session.volumeTotal > 0 {
                GeometryReader { proxy in
                    let used = CGFloat(session.volumeTotal - session.volumeFree) / CGFloat(session.volumeTotal)
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(Color(red: 0.20, green: 0.48, blue: 0.36))
                            .frame(width: max(4, proxy.size.width * min(max(used, 0), 1)))
                    }
                }
                .frame(height: 6)
                Text("\(Copy.used) \(Format.bytes(max(0, session.volumeTotal - session.volumeFree))) \(Copy.ofCapacity) \(Format.bytes(session.volumeTotal))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text("\(Format.bytes(session.volumeFree)) \(Copy.free)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                if session.rootIsVolume, session.allocBytes > (session.volumeTotal - session.volumeFree) * 105 / 100 {
                    Text(Copy.sharedCopies)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detail: some View {
        BoundedColumn {
            breadcrumb
            statusBar
            if session.unreadable > 2, !session.hideAccessNote {
                accessNote
            }
            TreemapView()
                .fitsRemainingHeight()
            footer
        }
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(GroveColor.canvas(scheme))
        .background {
            ContentLayoutInset { top, bottom in
                if abs(top - topInset) > 0.5 { topInset = top }
                if abs(bottom - bottomInset) > 0.5 { bottomInset = bottom }
            }
        }
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(session.snapshot.crumbs.enumerated()), id: \.element.id) { index, crumb in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        session.openCrumb(crumb.id)
                    } label: {
                        Text(crumb.name)
                            .font(.callout.weight(index == session.snapshot.crumbs.count - 1 ? .semibold : .regular))
                            .foregroundStyle(index == session.snapshot.crumbs.count - 1 ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(height: 36)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if session.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
            Text(session.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(session.tip)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 360, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private var accessNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
            Text(session.offerDiskAccess ? "\(Copy.accessTitle). \(Copy.accessBody)" : Copy.systemSkip)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            if session.offerDiskAccess {
                Button(Copy.accessButton, action: session.openPrivacySettings)
                    .controlSize(.small)
            }
            Button {
                session.hideAccessNote = true
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.45))
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 16) {
            if let selection = session.snapshot.selection {
                selectionSummary(selection)
                Spacer()
                if selection.isDirectory {
                    Button(Copy.openFolder) { session.activate(selection.id) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                } else {
                    Button(Copy.quickLook) { session.quickLook() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                Button(Copy.reveal) { session.reveal() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button(Copy.trash, role: .destructive) { session.trash() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(selection.protected)
            } else {
                Text(session.notice ?? Copy.hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func selectionSummary(_ selection: SelectionInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: selection.category.symbol)
                .font(.title3)
                .foregroundStyle(selection.category.color(in: scheme))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(selection.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Text("\(Format.bytes(selection.allocSize)) \(Copy.onDisk)")
                    Text(Format.share(selection.allocSize, of: max(session.snapshot.currentSize, 1)))
                    if selection.isDirectory {
                        Text(Format.files(selection.fileCount))
                    } else if selection.logicalSize > selection.allocSize + 1024 * 1024,
                              selection.allocSize * 4 < selection.logicalSize {
                        Text(Format.bytes(selection.logicalSize))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                session.goUp()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(session.snapshot.crumbs.count <= 1)
            .keyboardShortcut(.upArrow, modifiers: .command)
            .help(Copy.up)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                session.openWelcome()
            } label: {
                Image(systemName: "house")
            }
            .help(Copy.home)
            if session.isScanning {
                Button(Copy.stop, action: session.stop)
            } else {
                Button {
                    session.rescan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(Copy.rescan)
            }
            Button {
                session.reveal()
            } label: {
                Image(systemName: "folder")
            }
            .disabled(session.selectedID == nil)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help(Copy.reveal)
            Button(role: .destructive) {
                session.trash()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(session.selectedID == nil)
            .keyboardShortcut(.delete, modifiers: .command)
            .help(Copy.trash)
            Button(action: session.chooseFolder) {
                Image(systemName: "folder.badge.plus")
            }
            .help(Copy.otherFolder)
        }
    }
}

private struct FitsColumn: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    /// The one child that shrinks so the path, status, and footer keep their height.
    fileprivate func fitsRemainingHeight() -> some View {
        layoutValue(key: FitsColumn.self, value: true)
    }
}

/// Pins the map to the space left after the breadcrumb, status, and footer.
/// Heights are measured while sizing. Measuring again while placing returns zero,
/// which previously let the map cover the whole window.
private struct BoundedColumn: Layout {
    struct Cache {
        var heights: [CGFloat] = []
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        // A zero-width pass makes the footer wrap into a thousand-point height, and
        // SwiftUI then uses that as the real column height, so the map leaves the window.
        let proposedWidth = proposal.width ?? 0
        let width = proposedWidth > 40 ? proposedWidth : 720
        let flexIndex = subviews.indices.first { subviews[$0][FitsColumn.self] }
        var heights = Array(repeating: CGFloat(0), count: subviews.count)
        var fixed: CGFloat = 0
        for index in subviews.indices where index != flexIndex {
            let height = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            heights[index] = height
            fixed += height
        }
        let bounded = proposal.height.map { $0.isFinite && $0 > 0 ? $0 : nil } ?? nil
        let height = bounded ?? (fixed + 420)
        if let flexIndex {
            heights[flexIndex] = max(0, height - fixed)
        }
        cache.heights = heights
        return CGSize(width: proposedWidth > 1 ? proposedWidth : width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let heights = cache.heights.count == subviews.count ? cache.heights : Array(repeating: CGFloat(0), count: subviews.count)
        var y = bounds.minY
        for index in subviews.indices {
            let height = heights[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: height)
            )
            y += height
        }
    }
}

/// Reports how far this view extends above the window area that sits below the toolbar.
private struct ContentLayoutInset: NSViewRepresentable {
    var onChange: (_ top: CGFloat, _ bottom: CGFloat) -> Void

    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: Probe, context: Context) {
        nsView.onChange = onChange
        nsView.report()
    }

    final class Probe: NSView {
        var onChange: ((_ top: CGFloat, _ bottom: CGFloat) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        override func layout() {
            super.layout()
            report()
        }

        func report() {
            guard let window else { return }
            let frame = convert(bounds, to: nil)
            let content = window.contentLayoutRect
            let top = max(0, frame.maxY - content.maxY)
            let bottom = max(0, content.minY - frame.minY)
            let callback = onChange
            DispatchQueue.main.async {
                callback?(top, bottom)
            }
        }
    }
}

private struct SidebarRow: View {
    @Environment(\.colorScheme) private var scheme
    var item: MapItem
    var maxSize: Int64

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.category.symbol)
                .foregroundStyle(item.category == .folder ? Color.secondary : item.category.color(in: scheme))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .lineLimit(1)
                if item.allocSize > 0 {
                    let fraction = min(max(CGFloat(item.allocSize) / CGFloat(max(maxSize, 1)), 0.04), 1)
                    Color.clear
                        .frame(height: 4)
                        .overlay {
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.quaternary)
                                    Capsule()
                                        .fill((item.category == .folder ? Color.secondary : item.category.color(in: scheme)).opacity(0.9))
                                        .frame(width: proxy.size.width * fraction)
                                }
                            }
                        }
                }
            }
            Spacer(minLength: 6)
            Text(Format.bytes(item.allocSize))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
