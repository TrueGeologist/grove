import CoreGraphics

struct TileRect {
    var id: Int64
    var rect: CGRect
    var depth: Int
}

enum TreemapLayout {
    /// Squarified treemap. Sizes map back to the original array order.
    static func rects(sizes: [Int64], in rect: CGRect) -> [CGRect] {
        var output = [CGRect](repeating: .zero, count: sizes.count)
        guard rect.width > 1, rect.height > 1 else { return output }

        var entries: [(index: Int, area: Double)] = []
        entries.reserveCapacity(sizes.count)
        var total: Double = 0
        for (index, size) in sizes.enumerated() where size > 0 {
            let area = Double(size)
            entries.append((index, area))
            total += area
        }
        guard total > 0 else { return output }

        let scale = Double(rect.width * rect.height) / total
        for index in entries.indices {
            entries[index].area *= scale
        }
        entries.sort { $0.area > $1.area }

        var cursor = 0
        var bounds = rect
        while cursor < entries.count {
            let alongWidth = bounds.width >= bounds.height
            let side = Double(alongWidth ? bounds.height : bounds.width)
            var row: [(index: Int, area: Double)] = []
            var rowArea = 0.0
            var next = cursor
            while next < entries.count {
                let candidate = entries[next]
                let grown = rowArea + candidate.area
                let trial = row + [candidate]
                if row.isEmpty || worst(row, sum: rowArea, side: side) >= worst(trial, sum: grown, side: side) {
                    row.append(candidate)
                    rowArea = grown
                    next += 1
                } else {
                    break
                }
            }
            place(row, rowArea: rowArea, alongWidth: alongWidth, bounds: &bounds, into: &output)
            cursor = next
        }
        for index in output.indices {
            let clipped = output[index].intersection(rect)
            output[index] = clipped.isNull || clipped.width < 0.5 || clipped.height < 0.5 ? .zero : clipped
        }
        return output
    }

    private static func fitted(_ lengths: [CGFloat], into limit: CGFloat) -> [CGFloat] {
        let sum = lengths.reduce(0, +)
        guard sum > limit, sum > 0 else { return lengths }
        let scale = limit / sum
        return lengths.map { $0 * scale }
    }

    private static func worst(_ row: [(index: Int, area: Double)], sum: Double, side: Double) -> Double {
        guard sum > 0, side > 0, let maxArea = row.map(\.area).max(), let minArea = row.map(\.area).min(), minArea > 0 else {
            return .greatestFiniteMagnitude
        }
        let sideSquared = side * side
        let sumSquared = sum * sum
        return max(sideSquared * maxArea / sumSquared, sumSquared / (sideSquared * minArea))
    }

    private static func place(
        _ row: [(index: Int, area: Double)],
        rowArea: Double,
        alongWidth: Bool,
        bounds: inout CGRect,
        into output: inout [CGRect]
    ) {
        guard rowArea > 0 else { return }
        let limit = bounds
        if alongWidth {
            let width = min(bounds.width, CGFloat(rowArea / Double(max(bounds.height, 1))))
            let heights = fitted(row.map { width > 0 ? CGFloat($0.area / Double(width)) : 0 }, into: bounds.height)
            var y = bounds.minY
            for (item, height) in zip(row, heights) {
                output[item.index] = CGRect(x: bounds.minX, y: y, width: width, height: height).intersection(limit)
                y += height
            }
            bounds = CGRect(
                x: bounds.minX + width,
                y: bounds.minY,
                width: max(0, bounds.width - width),
                height: bounds.height
            )
        } else {
            let height = min(bounds.height, CGFloat(rowArea / Double(max(bounds.width, 1))))
            let widths = fitted(row.map { height > 0 ? CGFloat($0.area / Double(height)) : 0 }, into: bounds.width)
            var x = bounds.minX
            for (item, width) in zip(row, widths) {
                output[item.index] = CGRect(x: x, y: bounds.minY, width: width, height: height).intersection(limit)
                x += width
            }
            bounds = CGRect(
                x: bounds.minX,
                y: bounds.minY + height,
                width: bounds.width,
                height: max(0, bounds.height - height)
            )
        }
    }
}
