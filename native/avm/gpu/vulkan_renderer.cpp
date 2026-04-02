#include "avm/gpu/gpu_renderer.h"
#include "avm/core/platform.h"
#include <SDL2/SDL.h>
#include <SDL2/SDL_vulkan.h>
#include <vector>
#include <stdexcept>
#include <cstring>
#include <algorithm>
#include <string>

#ifdef AVM_ENABLE_VULKAN
#include <vulkan/vulkan.h>

// macOS: tell MoltenVK to use portability subset extension
#if AVM_OS_MACOS
#  define AVM_VK_PORTABILITY 1
#endif

namespace avm::gpu {

class VulkanRenderer : public GpuRenderer {
public:
    VulkanRenderer(SDL_Window* window) : window_(window) {}
    ~VulkanRenderer() override { cleanup(); }

    bool init() override {
        if (!create_instance())   return false;
        if (!create_surface())    return false;
        if (!pick_gpu())          return false;
        if (!create_device())     return false;
        if (!create_swapchain())  return false;
        if (!create_renderpass()) return false;
        if (!create_framebuffers()) return false;
        if (!create_sync())       return false;
        ready_ = true;
        const char* renderer_type =
#if AVM_OS_MACOS
            "Vulkan (MoltenVK / Metal)";
#else
            "Vulkan";
#endif
        AVM_LOG_INFO("GPU renderer: %s", renderer_type);
        return true;
    }

    bool is_ready() const override { return ready_; }

    void present_frame(const FrameBuffer& fb) override {
        // Acquire next swapchain image
        uint32_t img_idx;
        VkResult res = vkAcquireNextImageKHR(device_, swapchain_,
            UINT64_MAX, img_available_[frame_], VK_NULL_HANDLE, &img_idx);
        if (res == VK_ERROR_OUT_OF_DATE_KHR) { handle_resize(0, 0); return; }

        // Upload framebuffer pixels to staging buffer then blit to swapchain
        // (abbreviated — full impl would use vkCmdCopyBufferToImage)

        VkSubmitInfo si{};
        si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
        VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        si.waitSemaphoreCount   = 1;
        si.pWaitSemaphores      = &img_available_[frame_];
        si.pWaitDstStageMask    = &wait_stage;
        si.commandBufferCount   = 1;
        si.pCommandBuffers      = &cmd_bufs_[img_idx];
        si.signalSemaphoreCount = 1;
        si.pSignalSemaphores    = &render_done_[frame_];

        vkWaitForFences(device_, 1, &fences_[frame_], VK_TRUE, UINT64_MAX);
        vkResetFences(device_, 1, &fences_[frame_]);
        vkQueueSubmit(gfx_queue_, 1, &si, fences_[frame_]);

        VkPresentInfoKHR pi{};
        pi.sType              = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
        pi.waitSemaphoreCount = 1;
        pi.pWaitSemaphores    = &render_done_[frame_];
        pi.swapchainCount     = 1;
        pi.pSwapchains        = &swapchain_;
        pi.pImageIndices      = &img_idx;
        vkQueuePresentKHR(gfx_queue_, &pi);

        frame_ = (frame_ + 1) % kFramesInFlight;
    }

    void handle_resize(int w, int h) override {
        vkDeviceWaitIdle(device_);
        destroy_swapchain_objects();
        create_swapchain();
        create_framebuffers();
    }

private:
    static constexpr int kFramesInFlight = 2;

    bool create_instance() {
        // Gather required extensions from SDL2
        uint32_t ext_count = 0;
        SDL_Vulkan_GetInstanceExtensions(window_, &ext_count, nullptr);
        std::vector<const char*> exts(ext_count);
        SDL_Vulkan_GetInstanceExtensions(window_, &ext_count, exts.data());

#ifdef AVM_VK_PORTABILITY
        // MoltenVK requires VK_KHR_portability_enumeration
        exts.push_back("VK_KHR_portability_enumeration");
        exts.push_back("VK_KHR_get_physical_device_properties2");
#endif

        VkApplicationInfo ai{};
        ai.sType              = VK_STRUCTURE_TYPE_APPLICATION_INFO;
        ai.pApplicationName   = "AVM";
        ai.applicationVersion = VK_MAKE_VERSION(0, 1, 0);
        ai.apiVersion         = VK_API_VERSION_1_2;

        VkInstanceCreateInfo ci{};
        ci.sType                   = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
        ci.pApplicationInfo        = &ai;
        ci.enabledExtensionCount   = static_cast<uint32_t>(exts.size());
        ci.ppEnabledExtensionNames = exts.data();
#ifdef AVM_VK_PORTABILITY
        ci.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
#endif
        return vkCreateInstance(&ci, nullptr, &instance_) == VK_SUCCESS;
    }

    bool create_surface() {
        return SDL_Vulkan_CreateSurface(window_, instance_, &surface_) == SDL_TRUE;
    }

    bool pick_gpu() {
        uint32_t n = 0;
        vkEnumeratePhysicalDevices(instance_, &n, nullptr);
        if (n == 0) return false;
        std::vector<VkPhysicalDevice> devs(n);
        vkEnumeratePhysicalDevices(instance_, &n, devs.data());

        // Prefer discrete GPU; Apple Silicon only has one device (Metal GPU)
        for (auto d : devs) {
            VkPhysicalDeviceProperties p;
            vkGetPhysicalDeviceProperties(d, &p);
            if (p.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
                phys_ = d; break;
            }
        }
        if (phys_ == VK_NULL_HANDLE) phys_ = devs[0]; // fallback: first device

        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(phys_, &props);
        AVM_LOG_INFO("Vulkan GPU: %s", props.deviceName);
        return true;
    }

    bool create_device() {
        // Find a graphics + present queue family
        uint32_t qfc = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(phys_, &qfc, nullptr);
        std::vector<VkQueueFamilyProperties> qfps(qfc);
        vkGetPhysicalDeviceQueueFamilyProperties(phys_, &qfc, qfps.data());

        for (uint32_t i = 0; i < qfc; ++i) {
            if (!(qfps[i].queueFlags & VK_QUEUE_GRAPHICS_BIT)) continue;
            VkBool32 present = false;
            vkGetPhysicalDeviceSurfaceSupportKHR(phys_, i, surface_, &present);
            if (present) { gfx_family_ = i; break; }
        }

        float prio = 1.f;
        VkDeviceQueueCreateInfo qci{};
        qci.sType            = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        qci.queueFamilyIndex = gfx_family_;
        qci.queueCount       = 1;
        qci.pQueuePriorities = &prio;

        std::vector<const char*> dev_exts = { VK_KHR_SWAPCHAIN_EXTENSION_NAME };
#ifdef AVM_VK_PORTABILITY
        dev_exts.push_back("VK_KHR_portability_subset");
#endif

        VkDeviceCreateInfo dci{};
        dci.sType                   = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        dci.queueCreateInfoCount    = 1;
        dci.pQueueCreateInfos       = &qci;
        dci.enabledExtensionCount   = static_cast<uint32_t>(dev_exts.size());
        dci.ppEnabledExtensionNames = dev_exts.data();

        if (vkCreateDevice(phys_, &dci, nullptr, &device_) != VK_SUCCESS)
            return false;
        vkGetDeviceQueue(device_, gfx_family_, 0, &gfx_queue_);
        return true;
    }

    bool create_swapchain() {
        VkSurfaceCapabilitiesKHR caps;
        vkGetPhysicalDeviceSurfaceCapabilitiesKHR(phys_, surface_, &caps);

        uint32_t fmt_count = 0;
        vkGetPhysicalDeviceSurfaceFormatsKHR(phys_, surface_, &fmt_count, nullptr);
        std::vector<VkSurfaceFormatKHR> fmts(fmt_count);
        vkGetPhysicalDeviceSurfaceFormatsKHR(phys_, surface_, &fmt_count, fmts.data());

        VkSurfaceFormatKHR chosen_fmt = fmts[0];
        for (auto& f : fmts)
            if (f.format == VK_FORMAT_B8G8R8A8_UNORM &&
                f.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
                { chosen_fmt = f; break; }

        // Present mode: Mailbox (triple-buffer) preferred; FIFO fallback
        uint32_t pm_count = 0;
        vkGetPhysicalDeviceSurfacePresentModesKHR(phys_, surface_, &pm_count, nullptr);
        std::vector<VkPresentModeKHR> pms(pm_count);
        vkGetPhysicalDeviceSurfacePresentModesKHR(phys_, surface_, &pm_count, pms.data());
        VkPresentModeKHR present_mode = VK_PRESENT_MODE_FIFO_KHR;
        for (auto m : pms)
            if (m == VK_PRESENT_MODE_MAILBOX_KHR) { present_mode = m; break; }

        swapchain_extent_ = caps.currentExtent;
        swapchain_format_ = chosen_fmt.format;

        VkSwapchainCreateInfoKHR sci{};
        sci.sType            = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
        sci.surface          = surface_;
        sci.minImageCount    = std::min(caps.minImageCount + 1, caps.maxImageCount);
        sci.imageFormat      = chosen_fmt.format;
        sci.imageColorSpace  = chosen_fmt.colorSpace;
        sci.imageExtent      = swapchain_extent_;
        sci.imageArrayLayers = 1;
        sci.imageUsage       = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
        sci.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
        sci.preTransform     = caps.currentTransform;
        sci.compositeAlpha   = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
        sci.presentMode      = present_mode;
        sci.clipped          = VK_TRUE;

        if (vkCreateSwapchainKHR(device_, &sci, nullptr, &swapchain_) != VK_SUCCESS)
            return false;

        uint32_t img_count = 0;
        vkGetSwapchainImagesKHR(device_, swapchain_, &img_count, nullptr);
        swapchain_images_.resize(img_count);
        vkGetSwapchainImagesKHR(device_, swapchain_, &img_count, swapchain_images_.data());
        return create_image_views();
    }

    bool create_image_views() {
        swapchain_views_.resize(swapchain_images_.size());
        for (size_t i = 0; i < swapchain_images_.size(); ++i) {
            VkImageViewCreateInfo vc{};
            vc.sType    = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
            vc.image    = swapchain_images_[i];
            vc.viewType = VK_IMAGE_VIEW_TYPE_2D;
            vc.format   = swapchain_format_;
            vc.subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 };
            if (vkCreateImageView(device_, &vc, nullptr, &swapchain_views_[i]) != VK_SUCCESS)
                return false;
        }
        return true;
    }

    bool create_renderpass() {
        VkAttachmentDescription att{};
        att.format         = swapchain_format_;
        att.samples        = VK_SAMPLE_COUNT_1_BIT;
        att.loadOp         = VK_ATTACHMENT_LOAD_OP_CLEAR;
        att.storeOp        = VK_ATTACHMENT_STORE_OP_STORE;
        att.initialLayout  = VK_IMAGE_LAYOUT_UNDEFINED;
        att.finalLayout    = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

        VkAttachmentReference ref{ 0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
        VkSubpassDescription  sub{};
        sub.pipelineBindPoint    = VK_PIPELINE_BIND_POINT_GRAPHICS;
        sub.colorAttachmentCount = 1;
        sub.pColorAttachments    = &ref;

        VkRenderPassCreateInfo rci{};
        rci.sType           = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
        rci.attachmentCount = 1;
        rci.pAttachments    = &att;
        rci.subpassCount    = 1;
        rci.pSubpasses      = &sub;
        return vkCreateRenderPass(device_, &rci, nullptr, &render_pass_) == VK_SUCCESS;
    }

    bool create_framebuffers() {
        framebuffers_.resize(swapchain_views_.size());
        for (size_t i = 0; i < swapchain_views_.size(); ++i) {
            VkFramebufferCreateInfo fci{};
            fci.sType           = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
            fci.renderPass      = render_pass_;
            fci.attachmentCount = 1;
            fci.pAttachments    = &swapchain_views_[i];
            fci.width           = swapchain_extent_.width;
            fci.height          = swapchain_extent_.height;
            fci.layers          = 1;
            if (vkCreateFramebuffer(device_, &fci, nullptr, &framebuffers_[i]) != VK_SUCCESS)
                return false;
        }

        // Command pool + buffers
        VkCommandPoolCreateInfo pci{};
        pci.sType            = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
        pci.queueFamilyIndex = gfx_family_;
        pci.flags            = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
        vkCreateCommandPool(device_, &pci, nullptr, &cmd_pool_);

        cmd_bufs_.resize(framebuffers_.size());
        VkCommandBufferAllocateInfo ai{};
        ai.sType              = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        ai.commandPool        = cmd_pool_;
        ai.level              = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        ai.commandBufferCount = static_cast<uint32_t>(cmd_bufs_.size());
        return vkAllocateCommandBuffers(device_, &ai, cmd_bufs_.data()) == VK_SUCCESS;
    }

    bool create_sync() {
        img_available_.resize(kFramesInFlight);
        render_done_.resize(kFramesInFlight);
        fences_.resize(kFramesInFlight);
        VkSemaphoreCreateInfo sci{ VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
        VkFenceCreateInfo     fci{ VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
                                   nullptr, VK_FENCE_CREATE_SIGNALED_BIT };
        for (int i = 0; i < kFramesInFlight; ++i) {
            vkCreateSemaphore(device_, &sci, nullptr, &img_available_[i]);
            vkCreateSemaphore(device_, &sci, nullptr, &render_done_[i]);
            vkCreateFence(device_, &fci, nullptr, &fences_[i]);
        }
        return true;
    }

    void destroy_swapchain_objects() {
        for (auto fb : framebuffers_) vkDestroyFramebuffer(device_, fb, nullptr);
        for (auto iv : swapchain_views_) vkDestroyImageView(device_, iv, nullptr);
        vkDestroySwapchainKHR(device_, swapchain_, nullptr);
        framebuffers_.clear(); swapchain_views_.clear(); swapchain_images_.clear();
    }

    void cleanup() {
        if (!device_) return;
        vkDeviceWaitIdle(device_);
        for (int i = 0; i < kFramesInFlight; ++i) {
            vkDestroySemaphore(device_, img_available_[i], nullptr);
            vkDestroySemaphore(device_, render_done_[i], nullptr);
            vkDestroyFence(device_, fences_[i], nullptr);
        }
        if (cmd_pool_) vkDestroyCommandPool(device_, cmd_pool_, nullptr);
        if (render_pass_) vkDestroyRenderPass(device_, render_pass_, nullptr);
        destroy_swapchain_objects();
        vkDestroyDevice(device_, nullptr);
        vkDestroySurfaceKHR(instance_, surface_, nullptr);
        vkDestroyInstance(instance_, nullptr);
    }

    SDL_Window*    window_     = nullptr;
    VkInstance     instance_   = VK_NULL_HANDLE;
    VkSurfaceKHR   surface_    = VK_NULL_HANDLE;
    VkPhysicalDevice phys_     = VK_NULL_HANDLE;
    VkDevice       device_     = VK_NULL_HANDLE;
    VkQueue        gfx_queue_  = VK_NULL_HANDLE;
    uint32_t       gfx_family_ = 0;
    VkSwapchainKHR swapchain_  = VK_NULL_HANDLE;
    VkFormat       swapchain_format_;
    VkExtent2D     swapchain_extent_;
    VkRenderPass   render_pass_ = VK_NULL_HANDLE;
    VkCommandPool  cmd_pool_    = VK_NULL_HANDLE;
    std::vector<VkImage>       swapchain_images_;
    std::vector<VkImageView>   swapchain_views_;
    std::vector<VkFramebuffer> framebuffers_;
    std::vector<VkCommandBuffer> cmd_bufs_;
    std::vector<VkSemaphore>   img_available_;
    std::vector<VkSemaphore>   render_done_;
    std::vector<VkFence>       fences_;
    int  frame_ = 0;
    bool ready_ = false;
};

std::unique_ptr<GpuRenderer> make_vulkan_renderer(SDL_Window* w) {
    return std::make_unique<VulkanRenderer>(w);
}

} // namespace avm::gpu
#endif // AVM_ENABLE_VULKAN
