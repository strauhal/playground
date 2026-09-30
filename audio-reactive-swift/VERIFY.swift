// Run from the project directory: swift VERIFY.swift
import Foundation
import Metal
import AppKit
let source = try String(contentsOfFile: "Sources/AudioReactive/MetalVisualizer.swift", encoding: .utf8).components(separatedBy: "\"\"\"")[1]
let device = MTLCreateSystemDefaultDevice()!
let library = try device.makeLibrary(source: source, options: nil)
let descriptor = MTLRenderPipelineDescriptor()
descriptor.vertexFunction = library.makeFunction(name: "vertexMain")
descriptor.fragmentFunction = library.makeFunction(name: "fragmentMain")
descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 160, height: 100, mipmapped: false)
td.usage = [.renderTarget]
td.storageMode = .shared
let texture = device.makeTexture(descriptor: td)!
let queue = device.makeCommandQueue()!
for active: Float in [0,1] {
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    let command = queue.makeCommandBuffer()!
    let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
    var uniforms: [Float] = [160,100,2,0.4,0.3,active,0.1,0.4,0.3,0.3,0.4,0.1,0.2,0.3,0.5,0.4,0.5,0.2,0.4,0.7]
    encoder.setRenderPipelineState(pipeline)
    uniforms += [0.5,0.4,0.2,0.5,0.8]
    encoder.setFragmentBytes(&uniforms, length: 100, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    precondition(command.status == .completed, "\(String(describing: command.error))")
    var pixels = [UInt8](repeating: 0, count: 160*100*4)
    texture.getBytes(&pixels, bytesPerRow: 160*4, from: MTLRegionMake2D(0,0,160,100), mipmapLevel: 0)
    let lit = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 0 || pixels[$0+1] > 0 || pixels[$0+2] > 0 }.count
    precondition(active == 0 ? lit == 0 : lit > 100)
    print(active == 0 ? "Silence: exact black verified" : "Active: \(lit) colored pixels; GPU render completed")
    if active == 1 {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 640, bitsPerPixel: 32)!
        for i in stride(from: 0, to: pixels.count, by: 4) {
            bitmap.bitmapData![i] = pixels[i+2]
            bitmap.bitmapData![i+1] = pixels[i+1]
            bitmap.bitmapData![i+2] = pixels[i]
            bitmap.bitmapData![i+3] = 255
        }
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/ernest-visualizer-verification.png"))
    }
}
