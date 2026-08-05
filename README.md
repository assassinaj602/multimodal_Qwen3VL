# 🚀 Qwen3-VL Mobile Vision AI (On-Device Flutter App)

An ultra-fast, privacy-first **On-Device Multimodal Vision AI** Flutter application running **Qwen3-VL-2B-Instruct** locally on Android using hardware-accelerated C++ FFI bindings (`llama.cpp` + `llamadart`). Zero cloud APIs required!

---

## ✨ Features

- 📱 **100% On-Device Multimodal Inference**: Describe images, answer complex visual questions, and extract visual insights completely offline.
- ⚡ **Hardware Acceleration**: Optimized for `arm64-v8a` Android devices leveraging Vulkan & Impeller GPU backends.
- 🛑 **Real-Time Token Streaming & Generation Controls**: Stream text token-by-token with instant **Stop Generating** cancellation support.
- 🎨 **Modern ChatGPT-Style UI**: Modern dark-mode UI with sleek message bubbles, thumbnail attachments, and real-time status indicators.
- 🧪 **Live SATE AI Stress Testing Suite**: Built-in benchmark suite executing memory pressure injection and synthetic query fault recovery.

---

## 🛠️ Tech Stack & Architecture

| Layer | Technology |
| :--- | :--- |
| **Frontend Framework** | [Flutter](https://flutter.dev) (Dart 3.x, Material 3) |
| **Inference Engine** | [`llamadart`](https://pub.dev/packages/llamadart) / `llama.cpp` C++ FFI |
| **Native Toolchain** | Android NDK 28 (`Clang 19`), CMake 3.22, Ninja Build System |
| **Vision Model** | `Qwen3-VL-2B-Instruct-Q4_K_M.gguf` + `mmproj-F16.gguf` |
| **Architecture** | `arm64-v8a` (Android 10+ / API 26+) |

---

## 💥 Engineering Challenges & Solutions

### 1. Multimodal Tokenizer Marker Error (`mtmd_tokenize failed: rc=2`)
- **Challenge**: Standard LLaVA media markers (`<__media__>`) caused native C++ tokenization exceptions when processing Qwen3-VL GGUF models.
- **Solution**: Updated the vision marker configuration and migrated to `llamadart`'s structured `LlamaContentPart` API (`LlamaImageContent` + `LlamaTextContent`) which manages Qwen's specific `<|vision_start|><|image_pad|><|vision_end|>` placeholder sequence natively.

### 2. Missing Native M-RoPE Spatial Patch Merger Operators
- **Challenge**: Default pre-compiled Flutter AAR native libraries lacked recent C++ patches for Qwen3-VL spatial patch merging (M-RoPE position encodings).
- **Solution**: Cross-compiled latest `llama.cpp` master source for Android `arm64-v8a` using Android NDK 28 (`Clang 19`) & CMake Ninja, producing updated `libllama.so` & `libmtmd.so` shared libraries placed directly in `android/app/src/main/jniLibs/arm64-v8a/`.

### 3. EXIF Metadata & Image Decoding Crash in C++ `stb_image`
- **Challenge**: Raw camera JPEGs with dynamic EXIF orientation headers frequently crashed the native C++ image decoder during multimodal evaluation.
- **Solution**: Implemented GPU-accelerated image normalization via `dart:ui.instantiateImageCodec`, converting input images to clean baseline 512x512 PNG byte streams prior to native FFI handoff.

### 4. Android Gradle Java/Kotlin Compatibility
- **Challenge**: Kotlin Gradle compilation mismatches between Java 11 and Java 17 bytecode targets across Flutter plugin dependencies.
- **Solution**: Enforced JVM target parity across all Gradle subprojects by configuring `jvmTarget = JvmTarget.JVM_17` and `JavaVersion.VERSION_17` in `android/app/build.gradle.kts`.

---

## 📂 Model Setup Guide

To run the model on your Android device:

1. Download the model files from Hugging Face:
   - **Model GGUF**: `Qwen3VL-2B-Instruct-Q4_K_M.gguf`
   - **Vision Projector**: `mmproj-Qwen3VL-2B-Instruct-F16.gguf`
2. Push the `.gguf` files to your app's external storage directory on the device:
   ```bash
   adb push Qwen3VL-2B-Instruct-Q4_K_M.gguf /sdcard/Android/data/com.example.multimodal_demo/files/model.gguf
   adb push mmproj-Qwen3VL-2B-Instruct-F16.gguf /sdcard/Android/data/com.example.multimodal_demo/files/mmproj.gguf
   ```
3. Run the app in release mode:
   ```bash
   flutter run --release
   ```

---

## 📄 License

Licensed under the [MIT License](LICENSE).
