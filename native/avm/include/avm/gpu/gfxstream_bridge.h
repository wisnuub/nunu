#pragma once
#include <cstdint>
#include <cstddef>
#include <memory>
#include <thread>
#include <atomic>
#include <mutex>
#include <queue>
#include <vector>
#include <functional>

namespace avm {

class GpuRenderer;

/**
 * CommandBuffer — a single serialized GPU command batch from the guest.
 */
struct CommandBuffer {
    std::vector<uint8_t> data;
    uint64_t             fence_id = 0;
};

/**
 * GfxstreamBridge — the host-side receive-and-decode engine for the
 * gfxstream GPU command stream.
 *
 * How it fits in the pipeline:
 *
 *   Android Game (guest)
 *       │  OpenGL ES / Vulkan calls
 *       ▼
 *   gfxstream guest encoder (virtio-gpu guest driver)
 *       │  serialized command buffers via virtio-gpu shared memory
 *       ▼
 *   GfxstreamBridge::receive_buffer()   <— called by QEMU virtio-gpu backend
 *       │  queued into ring buffer
 *       ▼
 *   Decode thread: GfxstreamBridge::decode_loop()
 *       │  deserializes commands, calls GpuRenderer
 *       ▼
 *   GpuRenderer::process_command_buffer()  (Vulkan or OpenGL host)
 *       │
 *       ▼
 *   Frame presented to host window
 *
 * Flow control:
 *   The bridge tracks guest fence IDs and signals them back when the
 *   host GPU completes the corresponding work. This prevents the guest
 *   from overrunning the host GPU queue (key for smooth 60fps gaming).
 */
class GfxstreamBridge {
public:
    explicit GfxstreamBridge(GpuRenderer* renderer);
    ~GfxstreamBridge();

    /**
     * start() — launch the background decode thread.
     * Must be called after the renderer is initialized.
     */
    bool start();

    /** stop() — signal the decode thread to exit and join it. */
    void stop();

    /**
     * receive_buffer() — called by the virtio-gpu backend when the
     * guest submits a command buffer. Thread-safe.
     *
     * @param data     pointer to raw gfxstream command bytes
     * @param size     byte count
     * @param fence_id guest fence to signal on completion
     */
    void receive_buffer(const uint8_t* data, size_t size, uint64_t fence_id = 0);

    /**
     * signal_fence() — notify the guest that a fence has been
     * signaled (host GPU work complete). Typically called by the
     * renderer after vkQueueSubmit / glFinish.
     */
    void signal_fence(uint64_t fence_id);

    /** Register a callback to be invoked when a fence is signaled. */
    void set_fence_callback(std::function<void(uint64_t)> cb);

    /** Returns pending queue depth (for flow-control diagnostics). */
    size_t queue_depth() const;

    /** Returns cumulative frames decoded since start(). */
    uint64_t frames_decoded() const { return frames_decoded_.load(); }

private:
    void decode_loop();

    GpuRenderer*  renderer_;
    std::thread   decode_thread_;
    std::atomic<bool> running_{ false };
    std::atomic<uint64_t> frames_decoded_{ 0 };

    mutable std::mutex        queue_mutex_;
    std::queue<CommandBuffer> cmd_queue_;
    std::condition_variable   queue_cv_;

    std::function<void(uint64_t)> fence_callback_;

    // Flow control: max queued buffers before back-pressure
    static constexpr size_t kMaxQueueDepth = 8;
};

} // namespace avm
