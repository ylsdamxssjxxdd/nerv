# nerv
这是为eva提供后端的项目
用于编译llama.cpp whisper.cpp stable-diffusion.cpp用

## 目标
- 量产
- 补完

## 编译
git clone https://github.com/ylsdamxssjxxdd/nerv.git
cmake -B build .
cmake --build build --config Release -j24

## 更新后端时注意
- stable-diffusion.cpp 搜索 LOG_DEBUG("Using Vulkan backend");替换为如下代码
```cpp
#ifdef SD_USE_VULKAN
        LOG_DEBUG("Using Vulkan backend");
        int dev_count = ggml_backend_vk_get_device_count();
        int dev = 0;
        if (const char* s = getenv("GGML_VK_DEVICE")) {
            int v = atoi(s);
            if (v >= 0 && v < dev_count) dev = v;
        }
        // prefer a discrete NVIDIA device if available; fallback to first
        int preferred = -1;
        for (int i = 0; i < dev_count; ++i) {
            char desc[256] = {0};
            ggml_backend_vk_get_device_description(i, desc, sizeof(desc));
            // avoid SwiftShader/Software devices and prefer NVIDIA/GeForce/RTX naming
            std::string d(desc);
            if (d.find("NVIDIA") != std::string::npos || d.find("GeForce") != std::string::npos || d.find("RTX") != std::string::npos) {
                preferred = i;
                break;
            }
        }
        if (preferred >= 0) dev = preferred;
        // Log available devices
        for (int i = 0; i < dev_count; ++i) {
            char desc[256] = {0};
            ggml_backend_vk_get_device_description(i, desc, sizeof(desc));
            LOG_INFO("ggml_vulkan: %d = %s", i, desc);
        }
        backend = ggml_backend_vk_init(dev);
        if (!backend) {
            LOG_WARN("Failed to initialize Vulkan backend (device %d)", dev);
        } else {
            char desc[256] = {0};
            ggml_backend_vk_get_device_description(dev, desc, sizeof(desc));
            LOG_INFO("Vulkan selected device: %d - %s", dev, desc);
        }
#endif
```