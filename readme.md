# nerv
这是为eva提供后端的项目
用于编译llama.cpp whisper.cpp stable-diffusion.cpp用

## 目标
- 量产
- 补完

## 编译
build.bat 
默认只会编译cpu和vulkan版本，-d all 为所有版本

## 更新后端时注意
- llama.cpp 为了能在win7下运行
    - 使用mingw编译器 gcc 12版本以上
    - CMakeLists.txt中顶部添加 set(GGML_WIN_VER "0x601" CACHE STRING   "ggml: Windows version") 
    - common/CMakeLists.txt 搜索(${TARGET} PRIVATE ${LLAMA_COMMON_EXTRA_LIBS} PUBLIC llama Threads::Threads) 下面添加
```txt
if (WIN32)
    target_link_libraries(${TARGET} PUBLIC ws2_32)
endif()
```
    - 搜索 inline bool mmap::open(const char *path) 替换
```cpp

inline bool mmap::open(const char *path) {
  close();

#if defined(_WIN32)
  auto wpath = u8string_to_wstring(path);
  if (wpath.empty()) { return false; }

#if WINAPI_FAMILY_PARTITION(WINAPI_PARTITION_APP | WINAPI_PARTITION_SYSTEM | WINAPI_PARTITION_GAMES) && (_WIN32_WINNT >= _WIN32_WINNT_WIN8)
  hFile_ = ::CreateFile2(wpath.c_str(), GENERIC_READ, FILE_SHARE_READ,
                         OPEN_EXISTING, NULL);
#else
  hFile_ = ::CreateFileW(wpath.c_str(), GENERIC_READ, FILE_SHARE_READ, NULL,
                         OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
#endif
  if (hFile_ == INVALID_HANDLE_VALUE) { return false; }

  LARGE_INTEGER size{};
  if (!::GetFileSizeEx(hFile_, &size)) { return false; }
  // If the following line doesn't compile due to QuadPart, update Windows SDK.
  // See:
  // https://github.com/yhirose/cpp-httplib/issues/1903#issuecomment-2316520721
  if (static_cast<ULONGLONG>(size.QuadPart) >
      (std::numeric_limits<decltype(size_)>::max)()) {
    // `size_t` might be 32-bits, on 32-bits Windows.
    return false;
  }
  size_ = static_cast<size_t>(size.QuadPart);

#if WINAPI_FAMILY_PARTITION(WINAPI_PARTITION_APP | WINAPI_PARTITION_SYSTEM) && (_WIN32_WINNT >= _WIN32_WINNT_WIN8)
  hMapping_ =
      ::CreateFileMappingFromApp(hFile_, NULL, PAGE_READONLY, size_, NULL);
#else
  hMapping_ =
      ::CreateFileMappingW(hFile_, NULL, PAGE_READONLY, size.HighPart,
                           size.LowPart, NULL);
#endif
  // Special treatment for an empty file...
  if (hMapping_ == NULL && size_ == 0) {
    close();
    is_open_empty_file = true;
    return true;
  }

  if (hMapping_ == NULL) {
    close();
    return false;
  }

#if WINAPI_FAMILY_PARTITION(WINAPI_PARTITION_APP | WINAPI_PARTITION_SYSTEM) && (_WIN32_WINNT >= _WIN32_WINNT_WIN8)
  addr_ = ::MapViewOfFileFromApp(hMapping_, FILE_MAP_READ, 0, 0);
#else
  addr_ = ::MapViewOfFile(hMapping_, FILE_MAP_READ, 0, 0, 0);
#endif
  if (addr_ == nullptr) {
    close();
    return false;
  }
#else
  fd_ = ::open(path, O_RDONLY);
  if (fd_ == -1) { return false; }

  struct stat sb;
  if (fstat(fd_, &sb) == -1) {
    close();
    return false;
  }
  size_ = static_cast<size_t>(sb.st_size);

  addr_ = ::mmap(NULL, size_, PROT_READ, MAP_PRIVATE, fd_, 0);

  // Special treatment for an empty file...
  if (addr_ == MAP_FAILED && size_ == 0) {
    close();
    is_open_empty_file = true;
    return false;
  }
#endif

  return true;
}
```

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