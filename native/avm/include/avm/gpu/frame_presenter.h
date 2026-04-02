#pragma once
#include "gpu_renderer.h"
#include <cstdint>
#include <chrono>

namespace avm {

/**
 * FramePresenter — wraps the renderer's present_frame() call with
 * frame timing, FPS measurement, and optional vsync override.
 *
 * For gaming we want to:
 *  1. Present as fast as the host GPU can, decoupled from Android's
 *     60fps SurfaceFlinger vsync (vsync_override = true in Config).
 *  2. Measure both host FPS (actual render rate) and report it to
 *     the overlay UI.
 *  3. Optionally cap to a target FPS to avoid wasting GPU power on
 *     games that don't need 144fps (e.g., turn-based RPGs).
 */
class FramePresenter {
public:
    explicit FramePresenter(GpuRenderer* renderer,
                             int target_fps = 0,    // 0 = uncapped
                             bool vsync_override = true);

    /**
     * present() — submit the frame to the renderer.
     * Enforces FPS cap if target_fps > 0.
     * Returns the current measured FPS.
     */
    float present(const FrameBuffer& fb);

    float current_fps()   const { return fps_; }
    uint64_t frame_count() const { return frame_count_; }

private:
    GpuRenderer* renderer_;
    int          target_fps_;
    bool         vsync_override_;
    float        fps_          = 0.0f;
    uint64_t     frame_count_  = 0;

    using Clock    = std::chrono::steady_clock;
    using TimePoint = Clock::time_point;

    TimePoint last_frame_time_;
    TimePoint fps_window_start_;
    uint64_t  fps_window_frames_ = 0;
};

} // namespace avm
