import SwiftUI

/// Squarified treemap layout (Bruls, Huizing, van Wijk).
/// Produces rectangles whose areas are proportional to node sizes.
enum TreemapLayout {

    struct Cell: Identifiable {
        let id: UUID
        let node: FileNode
        let rect: CGRect
    }

    static func layout(nodes: [FileNode], in rect: CGRect) -> [Cell] {
        let total = nodes.reduce(Int64(0)) { $0 + $1.sizeBytes }
        guard total > 0, rect.width > 1, rect.height > 1 else { return [] }
        let sorted = nodes.filter { $0.sizeBytes > 0 }.sorted { $0.sizeBytes > $1.sizeBytes }
        let scale = Double(rect.width * rect.height) / Double(total)
        var cells: [Cell] = []
        var remaining = ArraySlice(sorted)
        var free = rect

        while !remaining.isEmpty {
            var row: [FileNode] = []
            var rowArea: Double = 0
            let side = Double(min(free.width, free.height))
            var bestWorst = Double.infinity

            while let next = remaining.first {
                let area = Double(next.sizeBytes) * scale
                let testWorst = worstAspect(row: row, extraArea: area, rowArea: rowArea + area, side: side, scale: scale)
                if testWorst <= bestWorst || row.isEmpty {
                    row.append(next)
                    rowArea += area
                    bestWorst = testWorst
                    remaining = remaining.dropFirst()
                } else {
                    break
                }
            }

            // Lay the row along the shorter side of the free rectangle.
            let horizontal = free.width >= free.height
            let thickness = rowArea / side
            var offset = 0.0
            for node in row {
                let area = Double(node.sizeBytes) * scale
                let length = thickness > 0 ? area / thickness : 0
                let cellRect: CGRect
                if horizontal {
                    cellRect = CGRect(x: free.minX, y: free.minY + offset,
                                      width: thickness, height: length)
                } else {
                    cellRect = CGRect(x: free.minX + offset, y: free.minY,
                                      width: length, height: thickness)
                }
                cells.append(Cell(id: node.id, node: node, rect: cellRect))
                offset += length
            }
            if horizontal {
                free = CGRect(x: free.minX + thickness, y: free.minY,
                              width: free.width - thickness, height: free.height)
            } else {
                free = CGRect(x: free.minX, y: free.minY + thickness,
                              width: free.width, height: free.height - thickness)
            }
            if free.width < 1 || free.height < 1 { break }
        }
        return cells
    }

    private static func worstAspect(row: [FileNode], extraArea: Double,
                                    rowArea: Double, side: Double, scale: Double) -> Double {
        guard rowArea > 0, side > 0 else { return .infinity }
        let thickness = rowArea / side
        var worst = 1.0
        var areas = row.map { Double($0.sizeBytes) * scale }
        areas.append(extraArea)
        for area in areas where area > 0 {
            let length = area / thickness
            let aspect = max(length / thickness, thickness / length)
            worst = max(worst, aspect)
        }
        return worst
    }
}
