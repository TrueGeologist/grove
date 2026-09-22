import SwiftUI

struct DrawTile: Identifiable {
    var id: Int64
    var item: MapItem
    var rect: CGRect
    var depth: Int
    var labelInHeader: Bool
}

struct TreemapView: View {
    @EnvironmentObject private var session: GroveSession
    @Environment(\.colorScheme) private var scheme
    @FocusState private var mapFocused: Bool
    @State private var hoverID: Int64?
    @State private var hoverPoint: CGPoint = .zero
    @State private var lastClick: (id: Int64, time: Date)?

    var body: some View {
        GeometryReader { geo in
            let tiles = layout(session.snapshot.mapItems, in: CGRect(origin: .zero, size: geo.size), depth: 0, capacity: session.snapshot.currentSize)
            ZStack(alignment: .topLeading) {
                Canvas { context, canvasSize in
                    let clip = CGRect(origin: .zero, size: canvasSize)
                    context.clip(to: Path(clip))
                    draw(tiles, in: context, clip: clip)
                }
                if session.snapshot.mapItems.isEmpty {
                    emptyState
                }
                if let tile = tiles.first(where: { $0.id == hoverID && !$0.item.isAggregate }) ?? tiles.first(where: { $0.id == hoverID }) {
                    tooltip(tile)
                        .offset(tooltipOrigin(tile: tile, in: geo.size))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture(count: 1).onEnded { value in
                guard let tile = hit(tiles, value.location), !tile.item.isAggregate else { return }
                mapFocused = true
                if let last = lastClick, last.id == tile.id, Date().timeIntervalSince(last.time) < 0.32 {
                    lastClick = nil
                    session.activate(tile.id)
                } else {
                    lastClick = (tile.id, Date())
                    session.select(tile.id)
                }
            })
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverPoint = location
                    hoverID = hit(tiles, location)?.id
                case .ended:
                    hoverID = nil
                }
            }
            .contextMenu {
                if let id = hoverID ?? session.selectedID, id > 0 {
                    Button(Copy.reveal) {
                        session.select(id)
                        session.reveal()
                    }
                    Button(Copy.quickLook) {
                        session.select(id)
                        session.quickLook()
                    }
                    Button(Copy.copyPath) {
                        session.select(id)
                        session.copySelectedPath()
                    }
                    Divider()
                    Button(Copy.trash, role: .destructive) {
                        session.select(id)
                        session.trash()
                    }
                }
            }
            .focusable()
            .focused($mapFocused)
            .onKeyPress(.return) {
                guard let id = session.selectedID else { return .ignored }
                session.activate(id)
                return .handled
            }
            .onKeyPress(.space) {
                session.quickLook()
                return .handled
            }
            .onKeyPress(.escape) {
                session.goUp()
                return .handled
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(GroveColor.canvas(scheme))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: session.isScanning ? "magnifyingglass" : "square.dashed")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(session.snapshot.filtering ? Copy.noMatches : Copy.emptyFolder)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tooltip(_ tile: DrawTile) -> some View {
        let whole = max(session.snapshot.currentSize, 1)
        return VStack(alignment: .leading, spacing: 2) {
            Text(tile.item.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            Text("\(Format.bytes(tile.item.allocSize)) \(Copy.onDisk) · \(Format.share(tile.item.allocSize, of: whole))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if tile.item.isDirectory {
                Text(Format.files(tile.item.fileCount))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if tile.item.logicalSize > tile.item.allocSize + 1024 * 1024, tile.item.allocSize * 4 < tile.item.logicalSize {
                Text("\(Format.bytes(tile.item.logicalSize))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        .frame(width: 230, alignment: .leading)
    }

    private func tooltipOrigin(tile: DrawTile, in size: CGSize) -> CGSize {
        let x = min(max(8, hoverPoint.x + 16), max(8, size.width - 240))
        let y = min(max(8, hoverPoint.y + 18), max(8, size.height - 78))
        return CGSize(width: x, height: y)
    }

    private func hit(_ tiles: [DrawTile], _ point: CGPoint) -> DrawTile? {
        tiles
            .filter { $0.rect.contains(point) }
            .min { lhs, rhs in
                let left = lhs.rect.width * lhs.rect.height
                let right = rhs.rect.width * rhs.rect.height
                if left == right { return lhs.depth > rhs.depth }
                return left < right
            }
    }

    private func layout(_ items: [MapItem], in rect: CGRect, depth: Int, capacity: Int64) -> [DrawTile] {
        guard rect.width > 2, rect.height > 2 else { return [] }
        var pieces = items.filter { $0.allocSize > 0 }
        let shown = pieces.reduce(Int64(0)) { $0 + $1.allocSize }
        let rest = capacity - shown
        if depth > 0, rest > max(capacity / 30, 64 * 1024) {
            pieces.append(
                MapItem(
                    id: -(capacity &+ Int64(depth) &+ 3),
                    name: "",
                    path: "",
                    allocSize: rest,
                    logicalSize: rest,
                    isDirectory: true,
                    category: .folder,
                    fileCount: 0,
                    children: [],
                    kind: .aggregate,
                    location: ""
                )
            )
        }
        let rects = TreemapLayout.rects(sizes: pieces.map(\.allocSize), in: rect)
        var tiles: [DrawTile] = []
        for (item, itemRect) in zip(pieces, rects) {
            let box = itemRect.insetBy(dx: 1.25, dy: 1.25).intersection(rect)
            guard !box.isNull, box.width >= 1, box.height >= 1 else { continue }
            if item.name.isEmpty { continue }
            let header = item.isDirectory && !item.children.isEmpty && box.width > 78 && box.height > 54
            tiles.append(DrawTile(id: item.id, item: item, rect: box, depth: depth, labelInHeader: header))
            if header || (item.isDirectory && !item.children.isEmpty && box.width > 28 && box.height > 28) {
                let top = header ? 20.0 : 3.0
                let inner = CGRect(
                    x: box.minX + 3,
                    y: box.minY + top,
                    width: box.width - 6,
                    height: box.height - top - 3
                )
                tiles.append(contentsOf: layout(item.children, in: inner, depth: depth + 1, capacity: item.allocSize))
            }
        }
        return tiles
    }

    private func draw(_ tiles: [DrawTile], in context: GraphicsContext, clip: CGRect) {
        for tile in tiles {
            let visible = tile.rect.intersection(clip)
            guard !visible.isNull, visible.width >= 1, visible.height >= 1 else { continue }
            let path = Path(roundedRect: visible, cornerRadius: min(6, visible.height / 3), style: .continuous)
            let fill = tile.item.isAggregate
                ? Color.gray.opacity(scheme == .dark ? 0.28 : 0.22)
                : GroveColor.tile(category: tile.item.category, name: tile.item.name, scheme: scheme)
            context.fill(path, with: .color(fill))
            if tile.id == hoverID {
                context.fill(path, with: .color(.white.opacity(scheme == .dark ? 0.10 : 0.16)))
            }
        }
        for tile in tiles where tile.id == session.selectedID {
            let visible = tile.rect.intersection(clip)
            guard !visible.isNull else { continue }
            let path = Path(roundedRect: visible.insetBy(dx: 0.5, dy: 0.5), cornerRadius: min(6, visible.height / 3), style: .continuous)
            context.stroke(path, with: .color(Color(red: 0.98, green: 0.99, blue: 0.96)), lineWidth: 2)
        }
        for tile in tiles {
            drawLabel(tile, in: context, clip: clip)
        }
    }

    private func drawLabel(_ tile: DrawTile, in context: GraphicsContext, clip: CGRect) {
        let visible = tile.rect.intersection(clip)
        guard !visible.isNull else { return }
        let titleColor = tile.item.isAggregate
            ? (scheme == .dark ? Color.white.opacity(0.85) : Color.black.opacity(0.7))
            : GroveColor.label(category: tile.item.category, scheme: scheme)
        let detailColor = tile.item.isAggregate
            ? titleColor.opacity(0.75)
            : GroveColor.secondaryLabel(category: tile.item.category, scheme: scheme)

        // Nested folders keep a single header line. A centered title would sit on top of the children.
        if !tile.item.children.isEmpty {
            guard tile.labelInHeader, visible.width > 88, visible.height > 46 else { return }
            let band = CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: 18)
            let sizeWidth: CGFloat = visible.width > 168 ? 76 : 0
            drawFitted(
                Text(tile.item.name).font(.system(size: 11, weight: .semibold)).foregroundColor(titleColor),
                in: CGRect(x: visible.minX + 7, y: visible.minY + 2, width: visible.width - 14 - sizeWidth, height: 14),
                context: context,
                limit: band
            )
            if sizeWidth > 0 {
                drawFitted(
                    Text(Format.bytes(tile.item.allocSize)).font(.system(size: 10, weight: .medium)).foregroundColor(detailColor),
                    in: CGRect(x: visible.maxX - sizeWidth - 6, y: visible.minY + 2, width: sizeWidth, height: 14),
                    context: context,
                    limit: band
                )
            }
            return
        }

        // Smaller blocks stay blank; the name and size appear in the hover tooltip.
        guard visible.width >= 72, visible.height >= 36 else { return }
        let showDetail = visible.width >= 96 && visible.height >= 52
        if !showDetail {
            drawFitted(
                Text(tile.item.name).font(.system(size: 11, weight: .semibold)).foregroundColor(titleColor),
                in: CGRect(x: visible.minX + 6, y: visible.midY - 7, width: visible.width - 12, height: 14),
                context: context,
                limit: visible.insetBy(dx: 4, dy: 3)
            )
            return
        }
        let titleRect = CGRect(x: visible.minX + 6, y: visible.midY - 15, width: visible.width - 12, height: 14)
        drawFitted(
            Text(tile.item.name).font(.system(size: 11, weight: .semibold)).foregroundColor(titleColor),
            in: titleRect,
            context: context,
            limit: titleRect
        )
        drawFitted(
            Text(Format.bytes(tile.item.allocSize)).font(.system(size: 10, weight: .medium)).foregroundColor(detailColor),
            in: CGRect(x: titleRect.minX, y: titleRect.maxY + 1, width: titleRect.width, height: 13),
            context: context,
            limit: CGRect(x: titleRect.minX, y: titleRect.maxY + 1, width: titleRect.width, height: 13)
        )
    }

    private func drawFitted(_ text: Text, in rect: CGRect, context: GraphicsContext, limit: CGRect) {
        let box = rect.intersection(limit)
        guard !box.isNull, box.width > 8, box.height > 8 else { return }
        var context = context
        context.clip(to: Path(box))
        context.draw(text, in: box)
    }
}
