#include <iostream>
#include <string>
#include <memory>
#include "avm/core/vm_manager.h"
#include "avm/core/config.h"
#include "avm/core/platform.h"
#include "avm/core/android_version.h"
#include "avm/core/image_manager.h"
#include "avm/core/profile.h"

static void print_banner() {
    std::cout << R"(
    ___   _   ____  ___
   /   | | | / /  |/  /
  / /| | | |/ / /|_/ /
 / ___ |_|___/_/  /_/
/_/  |_(_)____/_/

Android Virtual Machine v0.1.0
)";
#if AVM_OS_MACOS && AVM_ARCH_ARM64
    std::cout << "Platform : macOS Apple Silicon (ARM64)\n";
#elif AVM_OS_MACOS
    std::cout << "Platform : macOS Intel (x86_64)\n";
#elif AVM_OS_WINDOWS
    std::cout << "Platform : Windows\n";
#else
    std::cout << "Platform : Linux\n";
#endif
    std::cout << std::endl;
}

static void print_usage(const char* prog) {
    std::cerr
        << "Usage: " << prog << " [options]\n\n"

        << "  Image & Version\n"
        << "    --image <path>        Path to Android system image (.img or SDK dir)\n"
        << "    --android <ver>       Target Android version\n"
        << "                          Examples: 13, android14, API33, tiramisu\n"
        << "    --list-versions       Print supported Android versions and exit\n\n"

        << "  Resources\n"
        << "    --memory <mb>         RAM in MB (default: 4096)\n"
        << "    --cores <n>           vCPU count (default: 4)\n\n"

        << "  Rendering\n"
        << "    --gpu vulkan|gl       Host GPU renderer (default: vulkan)\n"
        << "    --fps <n>             Target FPS cap, 0 = unlimited (default: 60)\n"
        << "    --fps-unlock          Alias for --fps 0\n\n"

        << "  Profiles\n"
        << "    --profile <name|path> Load a game/app profile from ~/.config/avm/profiles/\n"
        << "    --list-profiles       List saved profiles and exit\n\n"

        << "  Advanced\n"
        << "    --no-accel            Disable HW virtualization (slow, for testing)\n"
        << "    --kernel <path>       Kernel image (for custom goldfish/ranchu images)\n"
        << "    --initrd <path>       Ramdisk/initrd image\n"
        << "    --cmdline <args>      Kernel command-line arguments\n"
        << "    --help                Show this message\n\n";
}

int main(int argc, char* argv[]) {
    print_banner();

    avm::Config config;
    config.memory_mb       = 4096;
    config.vcpu_cores      = 4;
    config.gpu_backend     = avm::GpuBackend::Vulkan;
    config.hardware_accel  = true;
    config.android_version = avm::AndroidVersion::Auto;
    config.target_fps      = 60;

    std::string profile_arg;

    // ----------------------------------------------------------------
    // Argument parsing
    // ----------------------------------------------------------------
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];

        if (arg == "--help" || arg == "-h") {
            print_usage(argv[0]);
            return 0;
        }
        else if (arg == "--list-versions") {
            avm::print_version_table();
            return 0;
        }
        else if (arg == "--list-profiles") {
            auto profiles = avm::list_profiles();
            if (profiles.empty()) {
                std::cout << "No profiles found in: " << avm::profiles_dir() << "\n";
            } else {
                std::cout << "Profiles in " << avm::profiles_dir() << ":\n";
                for (auto& p : profiles) std::cout << "  " << p << "\n";
            }
            return 0;
        }
        else if (arg == "--image" && i + 1 < argc) {
            config.system_image_path = argv[++i];
        }
        else if ((arg == "--android") && i + 1 < argc) {
            std::string ver_str = argv[++i];
            config.android_version = avm::parse_android_version(ver_str);
            if (config.android_version == avm::AndroidVersion::Auto) {
                std::cerr << "[AVM] Unknown Android version: '" << ver_str << "'\n"
                          << "      Run --list-versions to see valid options.\n";
                return 1;
            }
            std::cout << "[AVM] Targeting: "
                      << avm::android_version_string(config.android_version) << "\n";
        }
        else if (arg == "--memory" && i + 1 < argc) {
            config.memory_mb = std::stoi(argv[++i]);
        }
        else if (arg == "--cores" && i + 1 < argc) {
            config.vcpu_cores = std::stoi(argv[++i]);
        }
        else if (arg == "--gpu" && i + 1 < argc) {
            std::string b = argv[++i];
            config.gpu_backend = (b == "gl")
                ? avm::GpuBackend::OpenGL
                : avm::GpuBackend::Vulkan;
        }
        else if (arg == "--fps" && i + 1 < argc) {
            config.target_fps = std::stoi(argv[++i]);
        }
        else if (arg == "--fps-unlock") {
            config.target_fps = 0;
            config.vsync_override = true;
        }
        else if (arg == "--profile" && i + 1 < argc) {
            profile_arg = argv[++i];
        }
        else if (arg == "--no-accel") {
            config.hardware_accel = false;
        }
        else if (arg == "--kernel" && i + 1 < argc) {
            config.kernel_path = argv[++i];
        }
        else if (arg == "--initrd" && i + 1 < argc) {
            config.initrd_path = argv[++i];
        }
        else if (arg == "--cmdline" && i + 1 < argc) {
            config.kernel_cmdline = argv[++i];
        }
        else {
            std::cerr << "[AVM] Unknown option: " << arg << "\n";
            print_usage(argv[0]);
            return 1;
        }
    }

    // ----------------------------------------------------------------
    // Load profile (before image validation so it can set --android)
    // ----------------------------------------------------------------
    if (!profile_arg.empty()) {
        avm::Profile profile;
        // Try as a full path first, then look in profiles_dir
        std::string profile_path = profile_arg;
        if (profile_path.find('/') == std::string::npos &&
            profile_path.find('\\') == std::string::npos) {
            profile_path = avm::profiles_dir() + "/" + profile_arg + ".json";
        }
        if (!avm::load_profile(profile_path, profile)) {
            std::cerr << "[AVM] Profile not found: " << profile_path << "\n";
            return 1;
        }
        avm::apply_profile(config, profile);
    }

    // ----------------------------------------------------------------
    // Require --image
    // ----------------------------------------------------------------
    if (config.system_image_path.empty()) {
        std::cerr << "[AVM] Error: --image is required.\n";
        print_usage(argv[0]);
        return 1;
    }

    // ----------------------------------------------------------------
    // Validate image + detect/apply version metadata
    // ----------------------------------------------------------------
    avm::ImageInfo img_info;
    if (!avm::ImageManager::validate(config.system_image_path, img_info)) {
        std::cerr << "[AVM] Image validation failed.\n";
        return 1;
    }

    if (config.android_version != avm::AndroidVersion::Auto)
        img_info.version = config.android_version;
    else
        config.android_version = img_info.version;

    avm::ImageManager::print_image_info(img_info);

    if (config.android_version != avm::AndroidVersion::Auto) {
        auto* vinfo = avm::find_version_info(config.android_version);
        if (vinfo) avm::ImageManager::apply_version_defaults(config, *vinfo);
    }

    if (!avm::ImageManager::check_arch_compat(img_info, config,
                                               !config.hardware_accel))
        return 1;

    // ----------------------------------------------------------------
    // Print final config
    // ----------------------------------------------------------------
    std::cout
        << "[AVM] Final config:\n"
        << "  Android  : " << avm::android_version_string(config.android_version) << "\n"
        << "  Image    : " << config.system_image_path << "\n"
        << "  Memory   : " << config.memory_mb << " MB\n"
        << "  vCPUs    : " << config.vcpu_cores << "\n"
        << "  GPU      : "
        << (config.gpu_backend == avm::GpuBackend::Vulkan ? "Vulkan" : "OpenGL") << "\n"
        << "  FPS cap  : "
        << (config.target_fps > 0 ? std::to_string(config.target_fps) + " fps"
                                  : "Unlimited") << "\n"
        << "  HW Accel : " << (config.hardware_accel ? "Yes" : "No") << "\n\n";

    // ----------------------------------------------------------------
    // Boot
    // ----------------------------------------------------------------
    auto vm = std::make_unique<avm::VmManager>(config);
    if (!vm->initialize()) {
        std::cerr << "[AVM] VM init failed.\n";
        return 1;
    }
    return vm->run();
}
