#include "avm/gpu/gfxstream_bridge.h"
#include "avm/gpu/gpu_renderer.h"
#include <iostream>
#include <condition_variable>

namespace avm {

// ============================================================
//  Construction / Destruction
// ============================================================

GfxstreamBridge::GfxstreamBridge(GpuRenderer* renderer)
    : renderer_(renderer) {}

GfxstreamBridge::~GfxstreamBridge() {
    stop();
}

// ============================================================
//  Lifecycle
// ============================================================

bool GfxstreamBridge::start() {
    if (running_) return true;
    running_ = true;
    decode_thread_ = std::thread(&GfxstreamBridge::decode_loop, this);
    std::cout << "[gfxstream] Decode thread started.\n";
    return true;
}

void GfxstreamBridge::stop() {
    if (!running_) return;
    running_ = false;
    queue_cv_.notify_all();
    if (decode_thread_.joinable()) decode_thread_.join();
    std::cout << "[gfxstream] Decode thread stopped. "
              << frames_decoded_.load() << " frames decoded total.\n";
}

// ============================================================
//  Buffer Submission (called from virtio-gpu backend / QEMU)
// ============================================================

void GfxstreamBridge::receive_buffer(const uint8_t* data,
                                      size_t         size,
                                      uint64_t       fence_id) {
    if (!data || size == 0) return;

    {
        std::unique_lock<std::mutex> lock(queue_mutex_);

        // Flow control: if the decode thread is falling behind,
        // apply back-pressure by blocking the caller briefly.
        // This prevents the guest from flooding the queue and
        // causing frame-drop spikes (key for stable gaming FPS).
        queue_cv_.wait(lock, [this] {
            return !running_ || cmd_queue_.size() < kMaxQueueDepth;
        });

        if (!running_) return;

        CommandBuffer cb;
        cb.data.assign(data, data + size);
        cb.fence_id = fence_id;
        cmd_queue_.push(std::move(cb));
    }
    queue_cv_.notify_one();
}

// ============================================================
//  Fence Signaling
// ============================================================

void GfxstreamBridge::signal_fence(uint64_t fence_id) {
    if (fence_id == 0) return;
    if (fence_callback_) fence_callback_(fence_id);
    // TODO: forward fence signal to QEMU virtio-gpu backend
    //       so the guest driver knows it can reuse the buffer.
    //       This will be wired to QEMU's qemu_bh_schedule() once
    //       we embed directly into QEMU's virtio-gpu device.
}

void GfxstreamBridge::set_fence_callback(std::function<void(uint64_t)> cb) {
    fence_callback_ = std::move(cb);
}

size_t GfxstreamBridge::queue_depth() const {
    std::unique_lock<std::mutex> lock(queue_mutex_);
    return cmd_queue_.size();
}

// ============================================================
//  Decode Loop (background thread)
// ============================================================

void GfxstreamBridge::decode_loop() {
    while (running_) {
        CommandBuffer cb;

        // Wait for a buffer to arrive
        {
            std::unique_lock<std::mutex> lock(queue_mutex_);
            queue_cv_.wait(lock, [this] {
                return !running_ || !cmd_queue_.empty();
            });
            if (!running_ && cmd_queue_.empty()) break;

            cb = std::move(cmd_queue_.front());
            cmd_queue_.pop();
        }
        // Notify the producer that there's space in the queue
        queue_cv_.notify_one();

        // --- Decode ---
        // Dispatch the serialized command buffer to the host GPU renderer.
        // The renderer decodes individual GL/Vulkan commands from the
        // gfxstream wire format and executes them on the host GPU.
        //
        // Wire format overview (gfxstream, from AOSP):
        //   Each command starts with:
        //     uint32_t opcode   — identifies the GL/VK function
        //     uint32_t dataLen  — byte length of the argument payload
        //   Followed by the packed argument bytes.
        //
        // Full decoder lives in:
        //   hardware/google/gfxstream/host/gl/OpenGLESDispatch/
        //   hardware/google/gfxstream/host/vulkan/
        //
        // For now we forward the raw buffer to the renderer;
        // the per-command dispatch will be added when we vendor
        // the gfxstream host library as a submodule.
        if (renderer_ && renderer_->is_ready()) {
            renderer_->process_command_buffer(cb.data.data(), cb.data.size());
        }

        // Signal the fence so the guest can recycle its buffer
        signal_fence(cb.fence_id);

        ++frames_decoded_;
    }
}

} // namespace avm
