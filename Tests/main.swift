import Foundation

assert(LidSensor.decode([1, 90, 0]) == 90)
assert(LidSensor.decode([1, 104, 1]) == 360)
assert(LidSensor.decode([1, 105, 1]) == nil)
assert(LidSensor.decode([1, 90]) == nil)
assert(LidSensor.decode([2, 90, 0]) == nil)
print("Sensor report checks passed")
assert(FoldMath.progress(angle: 120, start: 85, end: 5) == 0)
assert(FoldMath.progress(angle: 85, start: 85, end: 5) == 0)
assert(FoldMath.progress(angle: 45, start: 85, end: 5) == 0.5)
assert(FoldMath.progress(angle: 0, start: 85, end: 5) == 1)
assert(FoldMath.progress(angle: .nan, start: 85, end: 5) == 0)
assert(FoldMath.progress(angle: 45, start: 5, end: 85) == 0)
assert(FoldMath.progress(angle: 45, start: 5, end: 5) == 0)
for degrees in 0..<140 {
    assert(FoldMath.progress(angle: Double(degrees), start: 85, end: 5)
        >= FoldMath.progress(angle: Double(degrees + 1), start: 85, end: 5))
}
print("Fold mapping checks passed")
if CommandLine.arguments.contains("--sensor") {
    print("Lid angle: \(LidSensor().readAngle().map { "\($0)°" } ?? "unavailable")")
}
