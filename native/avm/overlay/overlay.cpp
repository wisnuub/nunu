#include <iostream>

/**
 * overlay.cpp — AVM in-game overlay UI.
 *
 * Renders on top of the emulated Android display using Dear ImGui.
 * Features:
 *  - FPS counter (host render fps vs guest reported fps)
 *  - CPU/GPU usage meters
 *  - Keymapper profile switcher
 *  - Multi-instance manager (launch/close VM instances)
 *  - Quick settings (resolution, FPS target, memory)
 *
 * TODO:
 *  - Integrate Dear ImGui with Vulkan or OpenGL host renderer
 *  - Implement FPS counter via frame timestamp delta
 *  - Hook into VmManager for multi-instance control
 *  - Build keymapper visual editor (drag handles over game screenshot)
 */

namespace avm {

class Overlay {
public:
    bool initialize() {
        std::cout << "[Overlay] ImGui overlay initialized. (stub)\n";
        // TODO: ImGui::CreateContext(), ImGui_ImplVulkan_Init(...)
        return true;
    }

    void render(float fps_host, float fps_guest, float cpu_pct, float gpu_pct) {
        (void)fps_host; (void)fps_guest; (void)cpu_pct; (void)gpu_pct;
        // TODO: ImGui::Begin("AVM"), render metrics, ImGui::End(), ImGui::Render()
    }

    void shutdown() {
        // TODO: ImGui::DestroyContext()
    }
};

} // namespace avm
