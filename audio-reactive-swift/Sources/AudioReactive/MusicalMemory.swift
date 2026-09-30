import Foundation

/// Thirty seconds of compact musical descriptors and their associated structural state.
/// No audio, images, or GPU history buffers are retained.
struct MusicalMemory {
    private var signatures = [SIMD4<Float>](repeating: .zero, count: 120)
    private var structures = [Float](repeating: 0, count: 120)
    private var cursor = 0
    private var count = 0
    private var clock: Double = 0
    private var baseline = SIMD4<Float>.zero
    private(set) var growth: Float = 0
    private(set) var dissolution: Float = 0
    private(set) var echo: Float = 0
    private(set) var recurrence: Float = 0

    mutating func advance(dt: Double, signature: SIMD4<Float>, structure: Float, audible: Bool) {
        guard dt.isFinite, dt >= 0, structure.isFinite,
              signature.x.isFinite, signature.y.isFinite, signature.z.isFinite, signature.w.isFinite,
              growth.isFinite, dissolution.isFinite, echo.isFinite, recurrence.isFinite,
              cursor >= 0, cursor < 120, count >= 0, count <= 120 else {
            self = MusicalMemory()
            return
        }
        guard audible else { return }
        let slow = Float(1-exp(-dt/5))
        if count == 0 { baseline = signature }
        let delta = signature-baseline
        let change = min(1, sqrt(delta.x*delta.x+delta.y*delta.y+delta.z*delta.z+delta.w*delta.w)*1.5)
        baseline += (signature-baseline)*slow
        clock += dt
        if clock >= 0.25 {
            clock.formTruncatingRemainder(dividingBy: 0.25)
            var weight: Float = 0
            var recalled: Float = 0
            var best: Float = 0
            // Exclude the last two seconds so an immediate neighbor isn't mistaken for recurrence.
            if count > 8 {
                for age in 8..<count {
                    let index = (cursor-1-age+120)%120
                    let d = signature-signatures[index]
                    let distance = d.x*d.x+d.y*d.y+d.z*d.z+d.w*d.w
                    let similarity = exp(-distance*18)
                    best = max(best,similarity)
                    let w = similarity*similarity
                    recalled += structures[index]*w
                    weight += w
                }
            }
            recurrence += (best-recurrence)*0.18
            if weight > 0.01 { echo += (recalled/weight-echo)*0.15 }
            signatures[cursor] = signature
            structures[cursor] = structure
            cursor = (cursor+1)%120
            count = min(120,count+1)
        }
        dissolution += (change-dissolution)*Float(1-exp(-dt/1.2))
        let goal = max(0,min(1,recurrence*(1-change)*0.8+signature.x*0.2))
        growth += (goal-growth)*Float(1-exp(-dt/2.5))
    }
}
