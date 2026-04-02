#include "avm/core/fps_limiter.h"
#include <thread>
#include <numeric>
#include <algorithm>

namespace avm {

FpsLimiter::FpsLimiter(int target_fps) {
    set_target(target_fps);
    reset();
}

void FpsLimiter::set_target(int fps) {
    target_fps_ = fps;
    if (fps > 0)
        frame_budget_ = std::chrono::nanoseconds(1'000'000'000LL / fps);
    else
        frame_budget_ = std::chrono::nanoseconds(0);
}

void FpsLimiter::reset() {
    next_frame_ = Clock::now();
    frame_count_ = 0;
    std::fill(std::begin(frame_times_), std::end(frame_times_), 0.0);
    ft_head_ = 0;
    measured_fps_ = 0.0;
}

void FpsLimiter::wait() {
    auto frame_start = Clock::now();

    if (target_fps_ > 0) {
        next_frame_ += frame_budget_;

        // If we're more than one frame behind (e.g. after a stall), reset
        // the deadline to now + budget to avoid a burst of frames.
        auto now = Clock::now();
        if (next_frame_ < now)
            next_frame_ = now + frame_budget_;

        // Sleep until ~1 ms before deadline, then spin
        constexpr auto kSpinThreshold = std::chrono::microseconds(1000);
        auto sleep_until = next_frame_ - kSpinThreshold;
        if (sleep_until > now)
            std::this_thread::sleep_until(sleep_until);

        // Spin for the last 1 ms to hit the deadline precisely
        while (Clock::now() < next_frame_) {
            // busy wait — intentional for sub-ms precision
        }
    }

    ++frame_count_;
    auto frame_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
        Clock::now() - frame_start).count();
    update_measured(static_cast<double>(frame_ns));
}

void FpsLimiter::update_measured(double frame_ns) {
    frame_times_[ft_head_] = frame_ns;
    ft_head_ = (ft_head_ + 1) % kWindow;

    // Compute average only once the window is full
    if (frame_count_ >= kWindow) {
        double total = 0;
        for (auto t : frame_times_) total += t;
        double avg_ns = total / kWindow;
        measured_fps_ = avg_ns > 0 ? 1e9 / avg_ns : 0.0;
    }
}

} // namespace avm
