cmake -B build/build-vulkan -DGGML_VULKAN=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DLLAMA_CURL=OFF
cmake --build build --config Release -j24