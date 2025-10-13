这是为机体eva提供后端的项目
用于编译llama.cpp whisper.cpp stable-diffusion.cpp用
当前版本
llama.cpp b6746
whisper.cpp 1.8.1 
stable-diffusion.cpp master-320-1c32fa0

尽可能发现支持的设备，编译的产物放置于`EVA_BACKEND/` 目录中
- 按中央教条放置第三方程序：`EVA_BACKEND/<架构>/<系统>/<设备>/<项目>/`，例如：
  - `EVA_BACKEND/x86_64/win/cuda/llama.cpp/llama-server(.exe)`
  - 架构：`x86_64`、`x86_32`、`arm64`、`arm32`
  - 系统：`win`、`linux`
  - 设备：`cpu`、`cuda`、`vulkan`、`opencl`
  - 项目：如 `llama.cpp`、`whisper.cpp`、`stable-diffusion.cpp`

编码要求：不要尝试使用git创建分支或提交