# 使用Ubuntu作为基础镜像
FROM nvcr.io/nvidia/cuda:12.4.0-devel-ubuntu20.04
# 避免安装时交互提示
ENV DEBIAN_FRONTEND=noninteractive
# 安装系统依赖
RUN apt-get update && apt-get install -y \
    wget tar xz-utils \
    libxxf86vm-dev libxi-dev libx11-dev libglm-dev build-essential \
    python3 python3-pip python3-wheel \
    pkg-config git vim cmake ninja-build ffmpeg \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y \
    openssh-server libgl1-mesa-dev libxcb* libfreetype6-dev libfontconfig1-dev libmtdev-dev libinput-dev libudev-dev libdbus-1-dev libglu1-mesa-dev libegl1-mesa-dev libx11-dev libx11-xcb-dev libssl-dev freeglut3-dev libxkbcommon-x11-dev libxkbcommon-dev libxrender-dev libasound2-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libclang-dev llvm \
    && rm -rf /var/lib/apt/lists/*
    
# Install Vulkan SDK and cURL
RUN apt-get update && apt-get install -y \    
    libvulkan1 vulkan-validationlayers vulkan-tools 
RUN wget -qO - https://packages.lunarg.com/lunarg-signing-key-pub.asc | apt-key add - && \
    wget -qO /etc/apt/sources.list.d/lunarg-vulkan-1.3.283-focal.list https://packages.lunarg.com/vulkan/1.3.283/lunarg-vulkan-1.3.283-focal.list && \
    apt update -y && \
    apt-get install -y vulkan-sdk libcurl4-openssl-dev curl
#安装输入法插件
RUN apt-get update && apt-get install -y \    
    fcitx5 libfcitx5-qt-dev libfcitx-qt5-dev fcitx-frontend-qt5
#安装语音包
RUN apt-get update && apt-get install -y \    
    libspeechd2 speech-dispatcher speech-dispatcher-espeak-ng libspeechd-dev flite1-dev libasound2-dev libpulse-dev
#安装 用户空间中的文件系统
RUN apt-get install -y fuse libfuse2 

# 安装python包
RUN apt-get install -y --no-install-recommends nodejs libgl1-mesa-glx && \
    rm -rf /var/lib/apt/lists/* && \
    pip install --no-cache-dir \
    jupyterlab torch pandas numpy onnx llama_cpp_python pywebio fastapi uvicorn markitdown \
    sqlalchemy pymysql pymongo openpyxl requests Markdown scipy scikit-learn xlrd xlwt \
    reportlab matplotlib seaborn starlette pydantic jinja2 scrapy opencv-python pillow pygame \
    unidecode tqdm rich beautifulsoup4 python-docx python-pptx PyPDF2 pdf2docx -i https://pypi.tuna.tsinghua.edu.cn/simple

# 安装 Node.js 20.x（LTS）
RUN apt-get update && \
    apt-get install -y ca-certificates curl gnupg && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g @qwen-code/qwen-code
RUN apt-get update && apt-get install -y libxtst-dev
# 设置工作目录
WORKDIR /workspace
# 设置环境变量
ENV PATH=/distribution/Qt5.15.17-ubuntu20_04-amd64/bin:$PATH
ENV LD_LIBRARY_PATH=/distribution/Qt5.15.17-ubuntu20_04-amd64/lib:$LD_LIBRARY_PATH
ENV PATH=/distribution/cmake-3.31.7-linux-x86_64/bin:$PATH
ENV PATH=/distribution/opencv-4.10.0-x86-install/bin:$PATH
ENV LD_LIBRARY_PATH=/distribution/opencv-4.10.0-x86-install/lib:$LD_LIBRARY_PATH
CMD ["/bin/bash"]

# 镜像构建命令 docker build -t sjxx-qt-linux-x86:20251013-cuda -f Dockerfile .