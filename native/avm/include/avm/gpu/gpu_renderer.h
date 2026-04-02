#pragma once
#include <cstdint>
#include <cstddef>
#include <string>

namespace avm {

/**
 * FrameBuffer — a single decoded frame from the guest GPU pipeline.
 */
struct FrameBuffer {
    const uint8_t* data   = nullptr;  // RGBA8 pixel data
    int            width  = 0;
    int            height = 0;
    uint64_t       fence  = 0;        // gfxstream fence ID for sync
};

/**
 * GpuRenderer — abstract interface for host-side GPU rendering.
 *
 * The guest Android VM serializes OpenGL ES / Vulkan commands via
 * gfxstream over the virtio-gpu PCI device. The GpuRenderer receives
 * decoded commands and presents frames to the host display.
 *
 * Concrete implementations:
 *  - VulkanRenderer   (preferred — best performance, Vulkan 1.1+)
 *  - OpenGLRenderer   (fallback — desktop OpenGL 3.3+)
 */
class GpuRenderer {
public:
    virtual ~GpuRenderer() = default;

    /**
     * initialize() — create GPU context, window surface, swap chain.
     * @param width  initial display width  in pixels
     * @param height initial display height in pixels
     * @param title  window title string
     */
    virtual bool initialize(int width, int height, const std::string& title) = 0;

    virtual void shutdown() = 0;

    /**
     * process_command_buffer() — decode a gfxstream command buffer
     * from the guest and dispatch GPU calls on the host.
     * Called from the gfxstream bridge decode thread.
     */
    virtual void process_command_buffer(const uint8_t* cmdbuf, size_t size) = 0;

    /**
     * present_frame() — blit the decoded framebuffer to the host window.
     * Called after process_command_buffer() signals frame completion.
     */
    virtual void present_frame(const FrameBuffer& fb) = 0;

    /**
     * handle_resize() — called when the host window is resized.
     * The renderer should recreate the swap chain.
     */
    virtual void handle_resize(int new_width, int new_height) = 0;

    /** Returns true if the renderer is fully initialized. */
    virtual bool is_ready() const = 0;

    virtual const char* backend_name() const = 0;
};

} // namespace avm
