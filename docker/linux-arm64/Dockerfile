# 镜像构建命令 docker buildx build --platform linux/arm64 -t sjxx-qt-linux-arm:20251013-cpu -f Dockerfile .

# 使用Ubuntu作为基础镜像
FROM ubuntu:20.04

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
    
# Install Vulkan and cURL
RUN apt-get update && apt-get install -y \
    libvulkan1 libvulkan-dev mesa-vulkan-drivers \
    vulkan-validationlayers vulkan-tools \
    libcurl4-openssl-dev curl \
 && rm -rf /var/lib/apt/lists/*

#安装输入法插件
RUN apt-get update && apt-get install -y \    
    fcitx5 libfcitx5-qt-dev libfcitx-qt5-dev fcitx-frontend-qt5
#安装语音包
RUN apt-get update && apt-get install -y \    
    libspeechd2 speech-dispatcher speech-dispatcher-espeak-ng libspeechd-dev flite1-dev libasound2-dev libpulse-dev
#安装 用户空间中的文件系统
RUN apt-get install -y fuse libfuse2
#安装 文档处理
RUN apt-get install -y libreoffice && rm -rf /var/lib/apt/lists/*
RUN apt-get update && apt-get install -y libxml2-dev libxtst-dev zlib1g-dev
# 安装python包
RUN pip install --no-cache-dir \
    jupyterlab torch pandas numpy onnx llama_cpp_python pywebio fastapi uvicorn markitdown \
    sqlalchemy pymysql pymongo openpyxl requests Markdown scipy scikit-learn xlrd xlwt -i https://pypi.tuna.tsinghua.edu.cn/simple
RUN pip install --no-cache-dir \
    reportlab matplotlib seaborn starlette pydantic jinja2 pillow pygame \
    unidecode tqdm rich -i https://pypi.tuna.tsinghua.edu.cn/simple

# 补充安装
RUN apt-get update && apt-get install -y \  
    libjpeg-dev cimg-dev libgcrypt-dev libgpgme-dev nlohmann-json3-dev squashfs-tools ccache\
    && rm -rf /var/lib/apt/lists/*

# 安装osg相关
RUN apt-get update && apt-get install -y \  
    libgdal-dev libgeos-dev libsqlite3-dev protobuf-compiler libprotobuf-dev libtinyxml-dev libglew-dev zlibc zlib-gst\
    && rm -rf /var/lib/apt/lists/*
RUN apt-get update && apt-get install -y \  
    libzip-dev libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev libsdl2-ttf-dev\
    libavcodec-dev libavformat-dev libavutil-dev libavfilter-dev libavdevice-dev libswscale-dev libswresample-dev libpostproc-dev\
    libcairo2-dev libpoppler-glib-dev librsvg2-dev libgtk2.0-dev libgtkglext1-dev libpng-dev libtiff-dev\
    libgsl-dev libdcmtk-dev libsdl1.2-dev\
    && rm -rf /var/lib/apt/lists/*    
    
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

# 设置工作目录
WORKDIR /workspace
# 设置环境变量
ENV PATH=/distribution/Qt5.15.17-ubuntu20_04-arm64/bin:$PATH
ENV LD_LIBRARY_PATH=/distribution/Qt5.15.17-ubuntu20_04-arm64/lib:$LD_LIBRARY_PATH
ENV PATH=/distribution/cmake-3.31.7-linux-aarch64/bin:$PATH
ENV PATH=/distribution/opencv-4.10.0-arm-install/bin:$PATH
ENV LD_LIBRARY_PATH=/distribution/opencv-4.10.0-arm-install/lib:$LD_LIBRARY_PATH
ENV PATH=/distribution/patchelf-0.18.0-aarch64/bin:$PATH
CMD ["/bin/bash"]

# 镜像构建命令 docker buildx build --platform linux/arm64 -t sjxx-qt-linux-arm:20250622-cpu -f Dockerfile .