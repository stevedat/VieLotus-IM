#if canImport(CoreGraphics)
import Foundation
import CoreGraphics

/// Assign expanded touch regions without allowing a neighbour to steal a key's
/// visible face. Gap ownership is geometric, not UIKit subview traversal order.
public enum KeyboardHitGeometry {
    public static func accepts(_ point: CGPoint, key: CGRect, peers: [CGRect],
                               horizontalSlop: CGFloat = 24, verticalSlop: CGFloat = 16) -> Bool {
        guard !key.isEmpty, !key.isNull, !key.isInfinite else { return false }
        if key.contains(point) { return true }
        guard key.insetBy(dx: -horizontalSlop, dy: -verticalSlop).contains(point) else { return false }
        func distanceSquared(_ rect: CGRect) -> CGFloat {
            let dx = max(0, max(rect.minX - point.x, point.x - rect.maxX))
            let dy = max(0, max(rect.minY - point.y, point.y - rect.maxY))
            return dx * dx + dy * dy
        }
        let distance = distanceSquared(key)
        for peer in peers where peer != key && !peer.isEmpty && !peer.isNull && !peer.isInfinite {
            if peer.contains(point) { return false }
            let other = distanceSquared(peer)
            if other < distance { return false }
            if other == distance && (peer.minY < key.minY || (peer.minY == key.minY && peer.minX < key.minX)) {
                return false
            }
        }
        return true
    }
}
#endif
