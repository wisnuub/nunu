import Darwin
import Foundation
import Metal
import QuartzCore

/// Client-owned shared memory the engine writes RGBA frames into. The same pages
/// back an MTLBuffer, so the GPU samples the guest's pixels without any copy.
final class SharedFrame {
    let url: URL
    let length: Int
    let buffer: MTLBuffer
    private let pointer: UnsafeMutableRawPointer
    private let fd: Int32

    init?(device: MTLDevice, width: Int, height: Int) {
        let page = Int(getpagesize())
        length = (width * height * 4 + page - 1) / page * page
        Paths.ensure(Paths.run)
        Self.removeStale()
        url = Paths.run.appendingPathComponent("frame-\(getpid()).rgba")
        fd = open(url.path, O_RDWR | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { return nil }
        guard ftruncate(fd, off_t(length)) == 0,
              let p = mmap(nil, length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0), p != MAP_FAILED
        else { close(fd); return nil }
        guard let b = device.makeBuffer(bytesNoCopy: p, length: length,
                                        options: .storageModeShared, deallocator: nil)
        else { munmap(p, length); close(fd); return nil }
        pointer = p
        buffer = b
    }

    deinit {
        munmap(pointer, length)
        close(fd)
        unlink(url.path)
    }

    /// Frame files left behind by nunu processes that crashed.
    private static func removeStale() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Paths.run.path)) ?? []
        for name in files where name.hasPrefix("frame-") && name.hasSuffix(".rgba") {
            let pid = pid_t(name.dropFirst(6).dropLast(5)) ?? 0
            if pid != getpid(), !Engine.isAlive(pid) {
                try? FileManager.default.removeItem(at: Paths.run.appendingPathComponent(name))
            }
        }
    }

    /// `url.path` is absolute, so this is file:///Users/...
    var handle: String { "file://" + url.path }

    func texture(width: Int, height: Int) -> MTLTexture? {
        guard width > 0, height > 0, width * height * 4 <= length else { return nil }
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        d.storageMode = .shared
        d.usage = .shaderRead
        return buffer.makeTexture(descriptor: d, offset: 0, bytesPerRow: width * 4)
    }
}

/// Draws the current guest frame into a CAMetalLayer, aspect-fit and letterboxed.
/// Called from the frame stream's thread on every new frame, and from the main
/// thread on resize; a serial queue keeps the two from overlapping.
final class FrameRenderer: @unchecked Sendable {
    let device: MTLDevice
    let layer: CAMetalLayer
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let renderQueue = DispatchQueue(label: "nunu.render", qos: .userInteractive)

    private var shared: SharedFrame?
    private var texture: MTLTexture?
    private(set) var frameSize = CGSize.zero

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue

        layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.displaySyncEnabled = true
        layer.isOpaque = true
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)

        do {
            let lib = try device.makeLibrary(source: Self.shader, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = lib.makeFunction(name: "v_main")
            desc.fragmentFunction = lib.makeFunction(name: "f_main")
            desc.colorAttachments[0].pixelFormat = layer.pixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            FileHandle.standardError.write(Data("nunu: shader: \(error)\n".utf8))
            return nil
        }
        let s = MTLSamplerDescriptor()
        s.minFilter = .linear
        s.magFilter = .linear
        guard let sampler = device.makeSamplerState(descriptor: s) else { return nil }
        self.sampler = sampler
    }

    /// (Re)allocates the shared mapping for a device of this size. Rotation keeps
    /// the byte count, so one allocation covers both orientations.
    func prepare(width: Int, height: Int) -> SharedFrame? {
        renderQueue.sync {
            shared = SharedFrame(device: device, width: width, height: height)
            texture = nil
            frameSize = .zero
            return shared
        }
    }

    /// New pixels are in the mapping. Called on the stream thread.
    func frameArrived(width: Int, height: Int) {
        renderQueue.async { [self] in
            if texture?.width != width || texture?.height != height {
                texture = shared?.texture(width: width, height: height)
                frameSize = CGSize(width: width, height: height)
            }
            draw()
        }
    }

    func redraw() {
        renderQueue.async { [self] in draw() }
    }

    private func draw() {
        guard let texture, let drawable = layer.nextDrawable(),
              let cmd = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }

        let target = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        let fit = aspectFit(CGSize(width: texture.width, height: texture.height), in: CGRect(origin: .zero, size: target))
        // Rect in NDC: (left, top, right, bottom)
        var rect = SIMD4<Float>(
            Float(fit.minX / target.width * 2 - 1),
            Float(1 - fit.minY / target.height * 2),
            Float(fit.maxX / target.width * 2 - 1),
            Float(1 - fit.maxY / target.height * 2)
        )
        enc.setRenderPipelineState(pipeline)
        enc.setVertexBytes(&rect, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        enc.setFragmentTexture(texture, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct VOut { float4 pos [[position]]; float2 uv; };
    vertex VOut v_main(uint vid [[vertex_id]], constant float4 &rect [[buffer(0)]]) {
        float2 uv = float2(vid & 1, vid >> 1);
        VOut o;
        o.pos = float4(mix(rect.x, rect.z, uv.x), mix(rect.y, rect.w, uv.y), 0, 1);
        o.uv = uv;
        return o;
    }
    fragment float4 f_main(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler s [[sampler(0)]]) {
        return float4(tex.sample(s, in.uv).rgb, 1.0);
    }
    """
}

/// Largest rect with `content`'s aspect ratio centred in `bounds`.
func aspectFit(_ content: CGSize, in bounds: CGRect) -> CGRect {
    guard content.width > 0, content.height > 0 else { return bounds }
    let scale = min(bounds.width / content.width, bounds.height / content.height)
    let w = content.width * scale, h = content.height * scale
    return CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
}
