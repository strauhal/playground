import Foundation
@main struct VerifyLiquid {
    static func main() {
        var quiet = LiquidControl()
        var fast = LiquidControl()
        for i in 0..<3000 {
            let before = quiet.value
            let value = quiet.advance(to: i%2 == 0 ? 1 : 0, dt: 1.0/30, activity: 0)
            precondition(value.isFinite && abs(value-before) <= 0.22/30+0.00001)
        }
        quiet = LiquidControl()
        for _ in 0..<15 {
            _ = quiet.advance(to: 1, dt: 1.0/30, activity: 0)
            _ = fast.advance(to: 1, dt: 1.0/30, activity: 1)
        }
        precondition(fast.value > quiet.value*2)
        print("Liquid controls: slow-song speed limit and faster rhythmic response passed")
    }
}
