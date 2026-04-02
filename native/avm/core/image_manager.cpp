#include "avm/core/image_manager.h"
#include "avm/core/platform.h"

#include <iostream>
#include <fstream>
#include <iomanip>
#include <cstring>
#if !AVM_OS_WINDOWS
#  include <sys/stat.h>
#endif

namespace avm {

// -----------------------------------------------------------------------
// Magic byte detection helpers
// -----------------------------------------------------------------------

static bool detect_ext4(const uint8_t* hdr) {
    // ext4 superblock starts at offset 1024; magic = 0xEF53
    // For quick detection from the first 4 KB we'd need to read more,
    // but most Android system.img are sparse images.
    // Sparse image magic: 0xED26FF3A (little-endian)
    uint32_t magic;
    std::memcpy(&magic, hdr, 4);
    return magic == 0xED26FF3A; // Android sparse ext4
}

static bool detect_raw_disk(const uint8_t* hdr) {
    // MBR: last two bytes of first sector are 0x55 0xAA
    // We only have 16 bytes here, so check for GPT (offset 512 normally).
    // For raw disk images just accept anything non-sparse.
    (void)hdr;
    return true; // fallback: accept as raw disk
}

// -----------------------------------------------------------------------
// AndroidVersion detection from image properties
// -----------------------------------------------------------------------
// In a production implementation this would mount the image and read
// /system/build.prop. For now we use a heuristic: if the user passed
// --android we trust that; otherwise we return Auto.
static AndroidVersion detect_version_from_image(const std::string& /*path*/) {
    // TODO: parse build.prop from sparse image without mounting
    // (requires reimplementing Android's simg2img + ext4 reader)
    return AndroidVersion::Auto;
}

// -----------------------------------------------------------------------
// ImageManager::validate
// -----------------------------------------------------------------------
bool ImageManager::validate(const std::string& path, ImageInfo& out) {
    out.path = path;

#if !AVM_OS_WINDOWS
    // ── SDK image directory mode ─────────────────────────────────────────────
    // When the user passes a directory (e.g. the arm64-v8a system-images dir),
    // we trust the Android SDK emulator to read system.img / kernel-ranchu from
    // it directly.  No file-level validation needed.
    {
        struct stat st;
        if (stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode)) {
            out.size_bytes  = 0;
            out.is_writable = false;
            out.version     = detect_version_from_image(path);

            if (path.find("arm64")  != std::string::npos ||
                path.find("aarch64") != std::string::npos)
                out.arch = "arm64";
            else if (path.find("x86_64") != std::string::npos ||
                     path.find("x86")    != std::string::npos)
                out.arch = "x86_64";
            else
                out.arch = "arm64"; // default for SDK dirs

            std::cout << "[ImageManager] SDK image directory detected: " << path << "\n";
            return true;
        }
    }
#endif

    // ── Single image file mode ────────────────────────────────────────────────
    std::ifstream f(path, std::ios::binary | std::ios::ate);
    if (!f.is_open()) {
        std::cerr << "[ImageManager] Cannot open image: " << path << "\n";
        return false;
    }

    out.size_bytes = (uint64_t)f.tellg();

    if (out.size_bytes < 4096) {
        std::cerr << "[ImageManager] Image too small (" << out.size_bytes
                  << " bytes): " << path << "\n";
        return false;
    }

    // Read first 16 bytes for magic detection
    f.seekg(0, std::ios::beg);
    uint8_t hdr[16] = {};
    f.read(reinterpret_cast<char*>(hdr), sizeof(hdr));

    bool is_sparse = detect_ext4(hdr);
    bool is_raw    = !is_sparse && detect_raw_disk(hdr);
    (void)is_raw;

    out.version = detect_version_from_image(path);

    // Attempt to detect arch from filename heuristic
    // e.g. "system-arm64.img", "android14-x86_64.img"
    if (path.find("arm64")  != std::string::npos ||
        path.find("aarch64") != std::string::npos)
        out.arch = "arm64";
    else if (path.find("x86_64") != std::string::npos ||
             path.find("x86")    != std::string::npos)
        out.arch = "x86_64";
    else
        out.arch = "unknown";

    // Check writeability
    std::ofstream test(path, std::ios::binary | std::ios::app);
    out.is_writable = test.is_open();

    return true;
}

// -----------------------------------------------------------------------
// ImageManager::apply_version_defaults
// -----------------------------------------------------------------------
void ImageManager::apply_version_defaults(Config& config,
                                           const AndroidVersionInfo& info) {
    // Only bump memory/vCPUs if the user left them at defaults (4096 / 4)
    if (config.memory_mb == 4096 && info.recommended_ram_mb > 4096) {
        std::cout << "[ImageManager] Bumping RAM to "
                  << info.recommended_ram_mb
                  << " MB (recommended for " << info.release_name << ")\n";
        config.memory_mb = info.recommended_ram_mb;
    }
    if (config.vcpu_cores == 4 && info.recommended_vcpus > 4) {
        std::cout << "[ImageManager] Bumping vCPUs to "
                  << info.recommended_vcpus
                  << " (recommended for " << info.release_name << ")\n";
        config.vcpu_cores = info.recommended_vcpus;
    }
    config.android_version = info.version;
    config.android_api_level = info.api_level;
}

// -----------------------------------------------------------------------
// ImageManager::print_image_info
// -----------------------------------------------------------------------
void ImageManager::print_image_info(const ImageInfo& info) {
    double mb = (double)info.size_bytes / (1024.0 * 1024.0);
    std::cout << "[ImageManager] Image summary:\n"
              << "  Path:    " << info.path << "\n"
              << "  Size:    " << std::fixed << std::setprecision(1)
              << mb << " MB\n"
              << "  Arch:    " << info.arch << "\n"
              << "  Writable:" << (info.is_writable ? " yes" : " no (read-only)") << "\n"
              << "  Version: "
              << android_version_string(info.version) << "\n\n";
}

// -----------------------------------------------------------------------
// ImageManager::check_arch_compat
// -----------------------------------------------------------------------
bool ImageManager::check_arch_compat(const ImageInfo& info,
                                      const Config& config,
                                      bool allow_tcg_fallback) {
#if AVM_OS_MACOS && AVM_ARCH_ARM64
    if (info.arch == "x86_64") {
        std::cerr << "[ImageManager] WARNING: x86_64 image on Apple Silicon!\n"
                  << "  Hypervisor.framework only supports ARM64 guests.\n"
                  << "  Use an ARM64 (aarch64) Android image instead.\n";
        if (!allow_tcg_fallback) {
            std::cerr << "  To run anyway with software emulation (very slow):\n"
                      << "  avm --no-accel ...\n";
            return false;
        }
        std::cerr << "  Falling back to TCG software emulation (expect ~5% native speed).\n";
    }
#else
    (void)config; (void)allow_tcg_fallback;
    if (info.arch == "arm64" && !config.hardware_accel) {
        std::cerr << "[ImageManager] NOTE: ARM64 image on x86 host requires TCG "
                  << "(will be slow without hardware accel).\n";
    }
#endif
    return true;
}

} // namespace avm
