# APK Size Analysis & Distribution Strategy

## 1. Release APK Size Summary

Measurements taken from production release builds (`flutter build apk --release --split-per-abi` and `flutter build apk --release`):

| ABI / Variant | APK File Name | Size (Bytes) | Size (MB) | Net Delta vs Base |
| :--- | :--- | :--- | :--- | :--- |
| **Base Release (before native scanner)** | `iSmart-Messenger.apk` | 38,142,622 | **36.4 MB** | Baseline |
| **arm64-v8a (Split)** | `app-arm64-v8a-release.apk` | 59,673,152 | **56.9 MB** | **+20.5 MB** |
| **armeabi-v7a (Split)** | `app-armeabi-v7a-release.apk` | 50,267,316 | **47.9 MB** | **+11.5 MB** |
| **x86_64 (Split / Emulator)** | `app-x86_64-release.apk` | 96,356,920 | **91.9 MB** | **+55.5 MB** |
| **Universal (All ABIs combined)** | `app-release.apk` | 139,496,996 | **133.0 MB** | **+96.6 MB** |

> [!NOTE]
> **Correction on Initial Draft Report**:
> The earlier mention of "133 MB arm64" was actually the **Universal APK**, which packages all three ABIs together (`arm64-v8a` + `armeabi-v7a` + `x86_64`).
> The true standalone `arm64-v8a` release APK is **56.9 MB**, representing a net delta of only **+20.5 MB** over the baseline application.

---

## 2. Native Shared Libraries Breakdown (`lib/arm64-v8a/`)

Inspected via `tar -tvf` inside `app-arm64-v8a-release.apk`:

| Library | Uncompressed Size | Compressed (in APK) | Description |
| :--- | :--- | :--- | :--- |
| `libopencv_java4.so` | 20,228,944 bytes (~19.3 MB) | ~8.5 MB | Native OpenCV 4.9.0 core, image processing & codecs |
| `libc++_shared.so` | 1,027,408 bytes (~1.0 MB) | ~0.4 MB | C++ standard library runtime required by OpenCV |
| `libapp.so` | 13,632,400 bytes (~13.0 MB) | ~4.7 MB | AOT compiled Flutter Dart code (+65 KB vs base) |
| `libflutter.so` | 11,581,856 bytes (~11.0 MB) | ~4.4 MB | Flutter engine runtime |
| `libbarhopper_v3.so` | 4,946,720 bytes (~4.7 MB) | ~1.8 MB | Barcode / QR scanner engine |
| `libimage_processing_util_jni.so` | 32,544 bytes | ~12 KB | CameraX image processing JNI helper |
| `libdatastore_shared_counter.so` | 7,112 bytes | ~3 KB | Android Jetpack DataStore counter |
| `libsurface_util_jni.so` | 4,896 bytes | ~2 KB | CameraX surface utility JNI helper |

---

## 3. Distribution Recommendation

1. **Production Play Store / App Bundle (`.aab`)**:
   - Google Play will automatically generate per-device split APKs.
   - 64-bit Android devices (98%+ of active Android devices today) will download only the **~56.9 MB** `arm64-v8a` package.

2. **Direct APK Distribution (GitHub Releases / Direct Download)**:
   - **Recommended**: Ship `app-arm64-v8a-release.apk` (**56.9 MB**) as the primary Android download.
   - **Optional**: Provide `app-armeabi-v7a-release.apk` (**47.9 MB**) specifically for legacy 32-bit devices.
   - **Avoid**: Never distribute the **Universal APK** (**133 MB**), as it forces every user to download redundant native binaries for architectures they do not have.
