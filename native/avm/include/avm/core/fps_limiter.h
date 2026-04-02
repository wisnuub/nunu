#pragma once
// fps_limiter.h — Precise frame-rate limiter using a spin/sleep hybrid.
// Used by the host render loop to cap or uncap FPS independently of
// Android's vsync signal.
//
// Usage:
//   FpsLimiter limiter(60);   // target 60 fps
//   while (running) {
//       render_frame();
//       limiter.wait();       // sleeps/spins until next frame slot
//   }
//   std::cout << limiter.measured_fps() << " fps\n";

#include <chrono>
#include <cstdint>

namespace avm {

class FpsLimiter {
public:
    // target_fps = 0 means unlimited.
    explicit FpsLimiter(int target_fps = 60);

    void set_target(int fps);   // change at runtime (e.g. toggle unlock)
    int  target() const { return target_fps_; }

    // Call once per frame after rendering. Blocks until the next frame
    // deadline. Uses sleep_for + a tight spin loop for <1 ms precision.
    void wait();

    // Rolling average over the last 60 frames.
    double measured_fps() const { return measured_fps_; }

    // Total frames rendered since construction.
    uint64_t frame_count() const { return frame_count_; }

    // Reset timing (call after a long stall, e.g. window minimise).
    void reset();

private:
    using Clock     = std::chrono::steady_clock;
    using TimePoint = Clock::time_point;
    using Duration  = std::chrono::nanoseconds;

    int         target_fps_   = 60;
    Duration    frame_budget_ {};     // nanoseconds per frame
    TimePoint   next_frame_   {};
    uint64_t    frame_count_  = 0;

    // Rolling average
    static constexpr int kWindow = 60;
    double   frame_times_[kWindow] {};
    int      ft_head_ = 0;
    double   measured_fps_ = 0.0;

    void update_measured(double frame_ns);
};

} // namespace avm
