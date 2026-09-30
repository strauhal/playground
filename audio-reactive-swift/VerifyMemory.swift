import Foundation
@main struct VerifyMemory {
    static func main() {
        var memory = MusicalMemory()
        for _ in 0..<900 {
            memory.advance(dt: 1.0/30, signature: SIMD4(0.5,0.3,0.2,0.1), structure: 0.6, audible: true)
        }
        precondition(memory.recurrence > 0.9 && memory.growth > 0.6)
        let growth = memory.growth
        for _ in 0..<60 {
            memory.advance(dt: 1.0/30, signature: SIMD4(0.1,0.8,0.9,0.8), structure: 0.2, audible: true)
        }
        precondition(memory.dissolution > 0.4 && memory.growth < growth)
        let frozen = memory.growth
        memory.advance(dt: 10, signature: .zero, structure: 0, audible: false)
        precondition(memory.growth == frozen)
        for i in 0..<54000 {
            let x = Float(i%300)/300
            memory.advance(dt: 1.0/30, signature: SIMD4(x,0.4,0.3,0.2), structure: x, audible: true)
        }
        precondition(memory.growth.isFinite && memory.echo.isFinite)
        memory.advance(dt: 0.03, signature: SIMD4(.nan,0,0,0), structure: 0, audible: true)
        precondition(memory.growth == 0 && memory.echo == 0 && memory.recurrence == 0)
        print("Invalid memory input: buffer discarded safely")
        print("Memory: recurrence, erosion, silence and 30-minute simulated ring-buffer wrap passed")
    }
}
