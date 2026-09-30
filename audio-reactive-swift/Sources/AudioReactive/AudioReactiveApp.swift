import AppKit
import Combine
import MetalKit
import AVFoundation
import Accelerate

struct AudioFeatures {
    var bass = 0.0; var mid = 0.0; var treble = 0.0; var energy = 0.0; var flux = 0.0
    var brightness = 0.0; var texture = 0.0; var rhythm = 0.0; var gesture = 0
    var harmonicX = 0.0; var harmonicY = 0.0
    var pan = 0.0; var width = 0.0; var pace = 0.0
}

final class AudioAnalyzer: ObservableObject {
    @Published var features = AudioFeatures()
    @Published var inputName = "No input selected"
    private let engine = AVAudioEngine()
    private let publicationGate = DispatchSemaphore(value: 1)
    private var lastPublication = 0.0
    private var fft: FFTSetup?
    private var fftSize = 0
    private var spectrum = [Float]()
    private var combinedSpectrum = [Float]()
    private var window = [Float]()
    private var weighted = [Float]()
    private var real = [Float]()
    private var imaginary = [Float]()
    deinit { if let fft { vDSP_destroy_fftsetup(fft) } }
    private var previous = [Float](repeating: 0, count: 1024)
    private var smoothed = AudioFeatures()
    private var fluxMean = 0.0
    private var elapsed = 0.0
    private var lastGesture = -10.0
    private var interval = 0.5

    private var tapped = false
    func start() throws {
        guard !tapped else { return }
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw NSError(domain: "No audio input available", code: 1) }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.analyze(buffer)
        }
        tapped = true
        do { try engine.start() } catch { stop(); throw error }
        inputName = "Selected macOS input device"
    }

    func stop() { engine.stop(); if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false } }

    private func analyze(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let data = channels[0]
        guard buffer.frameLength >= 32 else { return }
        let n = 1 << Int(log2(Double(min(Int(buffer.frameLength), 1024))))
        var rms: Float = 0
        vDSP_rmsqv(data, 1, &rms, vDSP_Length(n))
        let stereo = buffer.format.channelCount >= 2
        var rightRMS = rms
        var correlation: Float = 0
        if stereo {
            vDSP_rmsqv(channels[1], 1, &rightRMS, vDSP_Length(n))
            vDSP_dotpr(data, 1, channels[1], 1, &correlation, vDSP_Length(n))
        }
        let leftPower = Double(rms*rms), rightPower = Double(rightRMS*rightRMS)
        let totalPower = leftPower+rightPower
        let energy = min(1, sqrt(totalPower/2)*7)
        let pan = totalPower > 1e-9 ? (rightPower-leftPower)/totalPower : 0
        let coherence = Double(correlation)/max(1e-9,Double(n)*Double(rms)*Double(rightRMS))
        let width = stereo && min(leftPower,rightPower) > 1e-9 ? min(1,max(0,(1-coherence)*0.5)) : 0
        if fftSize != n {
            if let fft { vDSP_destroy_fftsetup(fft) }
            fft = vDSP_create_fftsetup(vDSP_Length(log2(Float(n))), FFTRadix(kFFTRadix2))
            fftSize = n
            spectrum = Array(repeating: 0, count: n/2)
            combinedSpectrum = Array(repeating: 0, count: n/2)
            window = Array(repeating: 0, count: n)
            weighted = Array(repeating: 0, count: n)
            real = Array(repeating: 0, count: n/2)
            imaginary = Array(repeating: 0, count: n/2)
            vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        }
        let log2n = vDSP_Length(log2(Float(n)))
        guard let setup = fft else { return }
        // Combine channel power, not samples: opposite-phase stereo cannot cancel the analysis.
        for i in combinedSpectrum.indices { combinedSpectrum[i] = 0 }
        let channelCount = stereo ? 2 : 1
        for channel in 0..<channelCount {
        vDSP_vmul(channels[channel], 1, window, 1, &weighted, 1, vDSP_Length(n))
        weighted.withUnsafeBufferPointer { src in
            real.withUnsafeMutableBufferPointer { rp in
                imaginary.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    src.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    spectrum.withUnsafeMutableBufferPointer { dst in
                        vDSP_zvmags(&split, 1, dst.baseAddress!, 1, vDSP_Length(n / 2))
                    }
                }
            }
        }
        for i in spectrum.indices { combinedSpectrum[i] += spectrum[i]/Float(channelCount) }
        }
        for i in spectrum.indices { spectrum[i] = combinedSpectrum[i] }
        // Packed real FFT stores Nyquist in imaginary[0]; exclude it from bass/DC.
        spectrum[0] = 0
        let bands = { [self] (lo: Double, hi: Double) -> Double in
            let first = max(1, min(spectrum.count - 1, Int(lo * Double(n) / buffer.format.sampleRate)))
            let last = max(first + 1, min(spectrum.count, Int(hi * Double(n) / buffer.format.sampleRate)))
            let magnitude = Double(spectrum[first..<last].reduce(0, +)).squareRoot() / Double(n)
            return (magnitude * 8).clamped(to: 0...1)
        }
        let next = AudioFeatures(bass: bands(30, 250), mid: bands(250, 4000), treble: bands(4000, 16000), energy: energy, flux: 0)
        let magnitudes = spectrum.dropFirst().map { sqrt(Double($0)) / Double(n) }
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
        let binHz = buffer.format.sampleRate / Double(n)
        do {
            func follow(_ a: Double, _ b: Double, _ seconds: Double) -> Double {
                a + (b-a) * (1-exp(-duration/seconds))
            }
            self.elapsed += duration
            if self.previous.count != magnitudes.count { self.previous = Array(repeating: 0, count: magnitudes.count) }
            var novelty = 0.0, total = 0.0, centroid = 0.0, logSum = 0.0
            var harmonicX = 0.0, harmonicY = 0.0, harmonicWeight = 0.0
            for i in magnitudes.indices {
                let value = magnitudes[i]
                let frequency = Double(i+1)*binHz
                if frequency >= 100 && frequency <= 2500 {
                    let midi = 69+12*log2(frequency/440)
                    // Circle of fifths: nearby harmonic relationships produce nearby colors.
                    let angle = midi.rounded()*7/12 * 2 * Double.pi
                    let weight = value*value
                    harmonicX += cos(angle)*weight
                    harmonicY += sin(angle)*weight
                    harmonicWeight += weight
                }
                novelty += max(0, value-Double(self.previous[i]))
                self.previous[i] = Float(value)
                total += value
                centroid += value * Double(i+1) * binHz
                logSum += log(max(1e-9,value))
            }
            novelty /= max(0.02,total)
            let threshold = max(0.09,self.fluxMean*1.65)
            if next.energy > 0.012 && novelty > threshold && self.elapsed-self.lastGesture > 0.16 {
                let gap = self.elapsed-self.lastGesture
                if gap < 1.5 {
                    let regularity = exp(-abs(gap-self.interval)/max(0.1,self.interval))
                    self.smoothed.rhythm = self.smoothed.rhythm*0.65 + regularity*0.35
                    self.interval = self.interval*0.7+gap*0.3
                }
                self.lastGesture = self.elapsed
                self.smoothed.gesture += 1
            }
            self.fluxMean = follow(self.fluxMean,novelty,1.8)
            self.smoothed.rhythm *= exp(-duration/3)
            let paceGoal = self.elapsed-self.lastGesture < 1.5 ? min(1,max(0,(0.8-self.interval)/0.55))*self.smoothed.rhythm : 0
            self.smoothed.pace = follow(self.smoothed.pace,paceGoal,1.2)
            self.smoothed.pan = follow(self.smoothed.pan,pan,0.12)
            self.smoothed.width = follow(self.smoothed.width,width,0.4)
            self.smoothed.bass = follow(self.smoothed.bass,next.bass,0.025)
            self.smoothed.mid = follow(self.smoothed.mid,next.mid,0.05)
            self.smoothed.treble = follow(self.smoothed.treble,next.treble,0.22)
            self.smoothed.energy = follow(self.smoothed.energy,next.energy,0.025)
            self.smoothed.flux = follow(self.smoothed.flux,min(1,novelty),0.035)
            self.smoothed.brightness = follow(self.smoothed.brightness,min(1,centroid/max(1e-9,total)/6000),0.5)
            let flatness = exp(logSum/Double(magnitudes.count))/max(1e-9,total/Double(magnitudes.count))
            self.smoothed.texture = follow(self.smoothed.texture,min(1,flatness*3),0.6)
            self.smoothed.harmonicX = follow(self.smoothed.harmonicX,harmonicX/max(1e-9,harmonicWeight),1.2)
            self.smoothed.harmonicY = follow(self.smoothed.harmonicY,harmonicY/max(1e-9,harmonicWeight),1.2)
            let snapshot = self.smoothed
            // One pending UI publication maximum: never accumulate stale audio frames.
            if elapsed-lastPublication >= 1.0/30,
               publicationGate.wait(timeout: .now()) == .success {
                lastPublication = elapsed
                DispatchQueue.main.async {
                    self.features = snapshot
                    self.publicationGate.signal()
                }
            }
        }
    }
}

private extension Comparable { func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) } }



@main final class AudioReactiveApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let analyzer = AudioAnalyzer()
    private let renderer = Renderer()
    private var subscription: AnyCancellable?
    static func main() {
        let app = NSApplication.shared
        let delegate = AudioReactiveApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let item = NSMenuItem()
        let submenu = NSMenu()
        submenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 1100,height: 700),
                          styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        window.title = "ernest strauhal"
        window.isReleasedWhenClosed = false
        let view = MTKView(frame: window.contentView!.bounds, device: MTLCreateSystemDefaultDevice())
        view.autoresizingMask = [.width,.height]
        view.clearColor = MTLClearColorMake(0,0,0,1)
        view.preferredFramesPerSecond = 30
        view.autoResizeDrawable = false
        view.colorPixelFormat = .bgra8Unorm
        window.contentView = view
        do {
            try renderer.prepare(view)
            view.delegate = renderer
            subscription = analyzer.$features.sink { [weak self, weak view] features in
                self?.renderer.target = features
                if features.energy > 0.008 { view?.isPaused = false }
            }
            try analyzer.start()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Unable to start visualizer"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        subscription = nil
        analyzer.stop()
    }
}
