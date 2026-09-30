import Foundation

/// Critically damped control with bounded speed. Position and velocity remain
/// continuous even when the audio measurement changes abruptly.
struct LiquidControl {
    private(set) var value: Float = 0
    private var velocity: Float = 0
    mutating func advance(to target: Float, dt: Double, activity: Float) -> Float {
        guard target.isFinite, dt.isFinite, dt > 0 else { return value }
        let activity = max(0,min(1,activity))
        let omega: Float = 3 + activity*9
        let limit: Float = 0.22 + activity*1.5
        let count = max(1,Int(ceil(min(dt,0.1)/0.008)))
        let h = Float(min(dt,0.1))/Float(count)
        for _ in 0..<count {
            velocity += (omega*omega*(target-value)-2*omega*velocity)*h
            velocity = max(-limit,min(limit,velocity))
            value += velocity*h
        }
        return value
    }
}
