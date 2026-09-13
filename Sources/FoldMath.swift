import Foundation

enum FoldMath {
    static func progress(angle: Double, start: Double, end: Double) -> Double {
        guard angle.isFinite, start.isFinite, end.isFinite, start > end else { return 0 }
        return min(1, max(0, (start - angle) / (start - end)))
    }
}
