#include "avm/gpu/frame_presenter.h"
#include "avm/gpu/gpu_renderer.h"
#include <thread>

namespace avm {

FramePresenter::FramePresenter(GpuRenderer* renderer,
                                int          target_fps,
                                bool         vsync_override)
    : renderer_(renderer)
    , target_fps_(target_fps)
    , vsync_override_(vsync_override)
    , last_frame_time_(Clock::now())
    , fps_window_start_(Clock::now()) {}

float FramePresenter::present(const FrameBuffer& fb) {
    using namespace std::chrono;

    // --- FPS cap ---
    if (target_fps_ > 0) {
        auto frame_budget = duration<double>(1.0 / target_fps_);
        auto now          = Clock::now();
        auto elapsed      = now - last_frame_time_;
        if (elapsed < frame_budget) {
            // Sleep most of the remaining time, spin the last 0.5ms
            // for precision (avoids oversleeping on Windows/Linux)
            auto sleep_time = frame_budget - elapsed
                              - duration<double>(0.0005);
            if (sleep_time > duration<double>(0))
                std::this_thread::sleep_for(sleep_time);
            // Spin-wait for the exact time
            while (Clock::now() - last_frame_time_ < frame_budget) {}
        }
    }

    last_frame_time_ = Clock::now();

    renderer_->present_frame(fb);
    ++frame_count_;
    ++fps_window_frames_;

    // Update FPS measurement every second
    auto fps_elapsed = duration_cast<duration<float>>(
        Clock::now() - fps_window_start_).count();
    if (fps_elapsed >= 1.0f) {
        fps_              = fps_window_frames_ / fps_elapsed;
        fps_window_frames_ = 0;
        fps_window_start_  = Clock::now();
    }

    return fps_;
}

} // namespace avm
