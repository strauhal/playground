import AppKit
import MetalKit

final class Renderer: NSObject, MTKViewDelegate {
    var target = AudioFeatures()
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var last = CACurrentMediaTime()
    private var phase: Float = 0
    private var bass: Float = 0
    private var mid: Float = 0
    private var visibility: Float = 0
    private var silence: Double = 0
    private var displacement: Float = 0
    private var momentum: Float = 0
    private var brightness: Float = 0
    private var texture: Float = 0
    private var harmonicHue: Float = 0
    private var harmonicConfidence: Float = 0
    private var memory: Float = 0
    private var tension: Float = 0
    private var pan: Float = 0
    private var stereoWidth: Float = 0
    private var colorActivity: Float = 0
    private var colorTravel: Float = 0
    private var presence: Float = 0
    private var bassControl = LiquidControl()
    private var midControl = LiquidControl()
    private var bendControl = LiquidControl()
    private var tensionControl = LiquidControl()
    private var motionDrive: Float = 0
    private var history = MusicalMemory()
    private let inFlight = DispatchSemaphore(value: 2)

    func prepare(_ view: MTKView) throws {
        guard let device = view.device else { throw NSError(domain: "Metal unavailable", code: 1) }
        queue = device.makeCommandQueue()
        let library = try device.makeLibrary(source: Self.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertexMain")
        descriptor.fragmentFunction = library.makeFunction(name: "fragmentMain")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        let thermal = ProcessInfo.processInfo.thermalState
        let limited = thermal == .serious || thermal == .critical || ProcessInfo.processInfo.isLowPowerModeEnabled
        view.preferredFramesPerSecond = limited ? 24 : 30
        let width = max(1, view.bounds.width), height = max(1, view.bounds.height)
        let scale = min(1, (limited ? 900.0 : 1500.0)/max(width,height))
        let desired = CGSize(width: floor(width*scale), height: floor(height*scale))
        if view.drawableSize != desired { view.drawableSize = desired }
        guard inFlight.wait(timeout: .now()) == .success else { return }
        var submitted = false
        defer { if !submitted { inFlight.signal() } }
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - last)
        last = now
        func follow(_ value: Float, _ goal: Float, _ seconds: Double) -> Float {
            value + (goal - value) * Float(1 - exp(-dt / seconds))
        }
        // Rhythm shortens the body's response; isolated transients only give it a small impulse.
        let rhythm = Float(target.rhythm)
        let presenceGoal = min(1, max(0, Float(target.energy)*3.2 + Float(target.mid)*0.8 + Float(target.treble)*0.35))
        presence = follow(presence, presenceGoal, presenceGoal > presence ? 0.28 : 0.7)
        // Stereo is a compositional bias, not a camera pan. Keep the form centered.
        pan = follow(pan,Float(target.pan)*0.32,0.48)
        stereoWidth = follow(stereoWidth,Float(target.width),0.6)
        colorActivity = follow(colorActivity,Float(target.pace),1.2)
        colorTravel += Float(dt)*visibility*colorActivity*0.10
        colorTravel.formTruncatingRemainder(dividingBy: 1)
        // Compress input range so ordinary levels (e.g. 0.12) meaningfully shape the surface.
        let bassGoal = 1-exp(-Float(target.bass)*7)
        let midGoal = 1-exp(-Float(target.mid)*6)
        // Only sustained rhythmic activity loosens the rate limits.
        let responsiveness = min(1,motionDrive*rhythm*3)
        bass = bassControl.advance(to: bassGoal, dt: dt, activity: responsiveness)
        mid = midControl.advance(to: midGoal, dt: dt, activity: responsiveness)
        brightness = follow(brightness, Float(target.brightness), Double(0.85-colorActivity*0.60))
        texture = follow(texture, Float(target.texture), 0.8)
        let confidence = Float(hypot(target.harmonicX,target.harmonicY))
        harmonicConfidence = follow(harmonicConfidence, confidence, 1.5)
        if confidence > 0.08 {
            let hue = Float(atan2(target.harmonicY,target.harmonicX)/(2*Double.pi))
            var delta = hue-harmonicHue
            delta -= round(delta)
            harmonicHue += delta*Float(1-exp(-dt/Double(2.0-colorActivity*1.6)))
            harmonicHue -= floor(harmonicHue)
        }
        let step = Float(dt)
        // Continuous flow: no discrete onset impulses or position kicks.
        let flowGoal = min(1,Float(target.flux)*2.2)
        displacement = bendControl.advance(to: flowGoal*(0.025+responsiveness*0.12),
                                           dt: dt, activity: responsiveness)
        // Sustained loudness changes shape, not travel speed. Repeated spectral
        // changes build a motion envelope; a single accent cannot set it racing.
        let speedGoal = rhythm*flowGoal*0.8+flowGoal*flowGoal*0.25
        momentum = follow(momentum, speedGoal, speedGoal > momentum ? 0.45 : 0.65)
        motionDrive = follow(motionDrive, momentum, 0.9)
        silence = target.energy < 0.008 ? silence + dt : 0
        let goal: Float = silence > 0.08 ? 0 : (target.energy > 0.008 ? 1 : visibility)
        visibility = follow(visibility, goal, goal > visibility ? 0.12 : 0.11)
        if visibility < 0.002 { visibility = 0 }
        phase += step * visibility * (0.035 + motionDrive*1.8)
        // Persistent audio history, not a timer or a sequence of scenes.
        memory = follow(memory, bass*0.5+texture*0.3+rhythm*0.2, 4.5)
        tension = tensionControl.advance(to: min(1, momentum*0.55+abs(bass-memory)*1.5),
                                         dt: dt, activity: responsiveness)
        history.advance(dt: dt, signature: SIMD4(bass, mid, brightness, texture),
                        structure: memory*0.5+tension*0.5, audible: target.energy > 0.008)
        guard let pipeline, let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable, let command = queue?.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        var uniforms = [Float(view.drawableSize.width), Float(view.drawableSize.height), phase, bass, mid, visibility, displacement, momentum, brightness, texture, rhythm, Float(target.flux), harmonicHue, harmonicConfidence, memory, tension, history.growth, history.dissolution, history.echo, history.recurrence, pan, stereoWidth, colorTravel, colorActivity, presence]
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: 100, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        command.present(drawable)
        let gate = inFlight
        command.addCompletedHandler { _ in gate.signal() }
        submitted = true
        command.commit()
        if visibility == 0 { view.isPaused = true }
    }

    static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 position [[position]]; };
    struct U { float2 resolution; float time; float bass; float mid; float visibility; float impulse; float momentum; float brightness; float texture; float rhythm; float flux; float harmonicHue; float harmonicConfidence; float memory; float tension; float growth; float dissolution; float echo; float recurrence; float pan; float stereoWidth; float colorTravel; float colorActivity; float presence; };
    vertex V vertexMain(uint id [[vertex_id]]) {
        float2 p = id == 0 ? float2(-1,-1) : (id == 1 ? float2(3,-1) : float2(-1,3));
        return {float4(p,0,1)};
    }
    float smoothUnion(float a, float b, float k) {
        float h = clamp(0.5 + 0.5*(b-a)/k,0.0,1.0);
        return mix(b,a,h)-k*h*(1.0-h);
    }
    float field(float3 p, constant U& u) {
        float t = u.time;
        // Positive pan is screen-right; stereo decorrelation spreads the material.
        p.x -= u.pan*0.28;
        p.x /= 1.0+u.stereoWidth*0.22;
        // Bass adds volume, attacks trade width for height: an elastic, near-volume-preserving gesture.
        float stretch = 1.0+u.bass*0.85+u.impulse*0.5;
        float lift = 1.0+u.mid*0.55;
        p /= float3(rsqrt(stretch),lift,rsqrt(stretch));
        float twist = p.y*(0.25+u.texture*0.7+u.mid*0.9+0.35*sin(t*0.4))+u.impulse*1.6;
        p.xz = float2(cos(twist)*p.x-sin(twist)*p.z,sin(twist)*p.x+cos(twist)*p.z);
        float tilt = 0.55+0.25*sin(t*0.19);
        p.yz = float2(cos(tilt)*p.y-sin(tilt)*p.z,sin(tilt)*p.y+cos(tilt)*p.z);
        p.x += 0.16*sin(p.y*2+t*0.7)*(0.3+u.momentum);
        // A continuous folded surface, not a union of spheres. Bass thickens the
        // material, mids buckle it; tension opens it into connected ribbons.
        float frequency = 1.6+u.mid*0.65+u.memory*0.6+u.echo*0.4;
        float3 q = p*frequency;
        q.x += (1.1+u.mid*1.4)*sin(q.y*0.6+t*0.35)*u.tension;
        // Local pressure waves make attacks legible without flashing the whole image.
        q.z += u.impulse*1.3*sin(q.x*0.8-t*1.1);
        float wave = sin(q.x+t*0.27)*cos(q.y)
                   + sin(q.y-t*0.21)*cos(q.z)
                   + sin(q.z+t*0.17)*cos(q.x);
        // Familiar passages deposit material; new timbres erode it smoothly.
        float lateral = 1.0+u.pan*tanh(p.x)*0.35;
        float coverage = smoothstep(0.08,0.62,u.presence);
        float thickness = max(0.008,(0.02+u.bass*0.52+u.growth*0.26-u.dissolution*0.20)*lateral*coverage);
        float membrane = (abs(wave-(u.tension-0.4)*0.8)-thickness)/(frequency*4.5);
        // Broad volume extends beyond the viewport; holes still reveal true black.
        float aspect = u.resolution.x/max(1.0,u.resolution.y);
        float boundary = length(p/float3(2.8*max(1.0,aspect),2.8/max(0.5,min(1.0,aspect)),1.35+u.growth*0.3))-1.0;
        return max(membrane,boundary*0.65);
    }
    float3 palette(float x) {
        // RGB endpoints equivalent to #0ff, #f0f, #f00, #ff0, #00f.
        float3 colors[5] = {float3(0,1,1),float3(1,0,1),float3(1,0,0),float3(1,1,0),float3(0,0,1)};
        float v = fract(x)*5.0;
        int i = int(floor(v));
        return mix(colors[i], colors[(i+1)%5], smoothstep(0.0,1.0,fract(v)));
    }
    float hash3(float3 p) {
        p = fract(p*0.1031);
        p += dot(p,p.yzx+33.33);
        return fract((p.x+p.y)*p.z);
    }
    fragment float4 fragmentMain(V in [[stage_in]], constant U& u [[buffer(0)]]) {
        if (u.visibility == 0) return float4(0,0,0,1);
        float2 uv = (in.position.xy*2.0-u.resolution)/u.resolution.y;
        float3 origin = float3(0,0,4.8);
        float3 ray = normalize(float3(uv,-2.4));
        float travel = 1.3;
        bool hit = false;
        for (int i=0;i<80;i++) {
            float d = field(origin+ray*travel,u);
            if (d<0.002) { hit=true; break; }
            travel += max(d*0.4,0.001);
            if (travel>9.0) break;
        }
        if (!hit) return float4(0,0,0,1);
        float3 p = origin+ray*travel;
        // Silence dismantles the surface in spatially coherent fragments.
        // The remaining pieces keep their color until they disappear.
        float cell = hash3(floor(p*9.0+float3(u.time*0.18,-u.time*0.11,u.time*0.07)));
        float breakup = smoothstep(0.0,0.22,1.0-u.visibility);
        float sparse = smoothstep(0.05,0.45,u.presence);
        float holeThreshold = max(breakup,1.0-sparse);
        float material = smoothstep(holeThreshold-0.12,holeThreshold+0.12,cell);
        float e = 0.003;
        float3 n = normalize(float3(
            field(p+float3(e,0,0),u)-field(p-float3(e,0,0),u),
            field(p+float3(0,e,0),u)-field(p-float3(0,e,0),u),
            field(p+float3(0,0,e),u)-field(p-float3(0,0,e),u)));
        float3 light = normalize(float3(-2,3,4));
        float diffuse = max(0.0,dot(n,light));
        float rim = pow(1.0-max(0.0,dot(n,-ray)),2.0);
        float specular = pow(max(0.0,dot(reflect(-light,n),-ray)),40.0);
        // Color describes timbre and harmonic motion; attacks never drive brightness.
        float thermal = u.bass/(0.12+u.bass+u.mid);
        float base = thermal*0.65+u.brightness*0.35+u.memory*0.25;
        float harmonicShift = sin(u.harmonicHue*6.28318)*min(0.16,u.harmonicConfidence*0.4);
        float spread = 0.13+u.texture*0.16;
        float pigment = base+harmonicShift+(p.x+p.y*0.8)*spread+u.echo*u.recurrence*0.12+u.colorTravel;
        float3 color = palette(pigment)*smoothstep(0.03,0.5,u.presence)*material;
        color = color*(0.22+0.78*diffuse)+color*rim*0.3+float3(specular*0.35);
        float fragmentEdge = smoothstep(0.0,0.7,u.visibility);
        return float4(clamp(color,0.0,1.0)*fragmentEdge,1);
    }
    """
}
