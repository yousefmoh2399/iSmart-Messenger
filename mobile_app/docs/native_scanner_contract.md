# Cross-Platform Native Document Scanner Contract

**Channel Name**: `ismart/doc_scanner`  
**Current Implementations**:
- **Android**: `MainActivity.kt`, `ScannerActivity.kt`, `DocumentDetector.kt`, `ImageFilters.kt` (CameraX + OpenCV 4.9.0)
- **iOS**: `packages/doc_scanner_ios` (AVFoundation + Vision + CoreImage)

---

## 1. Design Principles & Invariants

1. **Path-Based Zero-Copy Contract**:
   - Only file paths and metadata are passed across the `MethodChannel`.
   - Raw byte arrays and Base64 strings are **never** passed across the channel.
   - The native camera writes the captured JPEG directly to disk without intermediate decode/re-encode.

2. **Upright Image Standard**:
   - Every file returned to or written for Dart must be upright when decoded by an EXIF-respecting reader (EXIF orientation 1 or upright pixel array).
   - Sensor rotation is handled entirely by the native layer.
   - `width` and `height` always describe the **upright** dimensions.

3. **Normalized Coordinate System**:
   - Quadrilateral corners (`corners`) are represented as an array of 8 floating-point numbers (`List<Double>`):
     `[tl_x, tl_y, tr_x, tr_y, br_x, br_y, bl_x, bl_y]`
   - Each value is normalized to the `[0.0, 1.0]` range relative to the upright image dimensions:
     - Top-Left: `(tl_x * width, tl_y * height)`
     - Top-Right: `(tr_x * width, tr_y * height)`
     - Bottom-Right: `(br_x * width, br_y * height)`
     - Bottom-Left: `(bl_x * width, bl_y * height)`
   - Origin `(0.0, 0.0)` is top-left, `(1.0, 1.0)` is bottom-right.

4. **Native Concurrency**:
   - Image processing operations (`warp`, `applyFilter`, `rotateLeft`) are executed off the main UI thread with a concurrency limit of 2 (semaphore-guarded).
   - Replies are dispatched back on the main thread.

---

## 2. Method Specifications

### `startScan`
Opens the custom full-screen native camera controller.

#### Arguments:
| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `destDir` | `String?` | No | App temp/cache dir | Directory where raw capture JPEGs will be saved. |
| `batch` | `Boolean` | No | `false` | If `true`, camera stays open after capture for multi-page batch scanning. |

#### Return Value:
- **Cancelled / Back pressed**: `null`
- **Single Mode (`batch == false`)**:
  ```json
  {
    "batch": false,
    "path": "/path/to/raw_<uuid>.jpg",
    "corners": [tl_x, tl_y, tr_x, tr_y, br_x, br_y, bl_x, bl_y],
    "width": 3024,
    "height": 4032
  }
  ```
- **Batch Mode (`batch == true`)**:
  ```json
  {
    "batch": true,
    "items": [
      {
        "path": "/path/to/raw_<uuid1>.jpg",
        "corners": [tl_x, tl_y, tr_x, tr_y, br_x, br_y, bl_x, bl_y],
        "width": 3024,
        "height": 4032
      },
      ...
    ]
  }
  ```

#### Error Codes:
- `SCANNER_BUSY`: Another scan session is already in progress (`pendingScannerResult != null`).
- `LAUNCH_FAILED`: Native UI controller / activity could not be launched.
- `SCANNER_FAILED`: Missing capture payload or corrupt result.

---

### `warp`
Performs perspective correction on a quadrilateral region and writes the rectified rectangle to disk.

#### Arguments:
| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `path` | `String` | Yes | - | Absolute path to the source image. |
| `corners` | `List<Double>` | Yes | - | 8 normalized doubles `[tl_x, tl_y, tr_x, tr_y, br_x, br_y, bl_x, bl_y]`. |
| `outPath` | `String` | Yes | - | Destination path for the warped JPEG. |
| `maxSide` | `Int` | No | `0` (full) | Max dimension (width or height) of output. When > 0, downsamples during warp for fast preview. |
| `quarterTurns` | `Int` | No | `0` | Number of 90-degree counter-clockwise rotations applied in-memory **before** writing. |

#### Invariants & Behavior:
- **Optimization**: If `maxSide > 0` and source image's longer dimension is `>= 2 * maxSide`, the decoder may decode at half scale (`IMREAD_REDUCED_COLOR_2` on Android, downscaled thumbnail decode on iOS).
- **Centroid Inset**: Points are inset by 0.5% (`0.005`) toward the quadrilateral centroid before warping to eliminate black edge slivers.
- **Output Dimensions**: Edge lengths are computed from Euclidean distances:
  - `maxWidth = max(dist(BR, BL), dist(TR, TL))`
  - `maxHeight = max(dist(TR, BR), dist(TL, BL))`
  - Scaled proportionally if `maxSide > 0`.
- **In-Memory Rotation**: `quarterTurns` rotates the Mat/CIImage in memory before saving, guaranteeing a 2-pass save sequence (`warp(+rotation) -> filter`).
- **File Output**: JPEG quality 95, sRGB color space, EXIF orientation 1.
- **Return Value**: `outPath` on success.

#### Error Codes:
- `INVALID_ARGS`: Missing or malformed parameters (`corners.size != 8`).
- `READ_FAILED`: Source image could not be loaded.
- `WRITE_FAILED`: Could not encode or write destination JPEG.
- `WARP_ERROR`: Transform failure or internal error.

---

### `applyFilter`
Applies an image enhancement or color transformation to a rectified document page.

#### Arguments:
| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `path` | `String` | Yes | - | Absolute path to the input rectified image. |
| `filter` | `String` | Yes | `"enhance"` | Filter identifier: `original`, `lighten`, `enhance`, `gray`, `eco`, `no_handwriting`. |
| `outPath` | `String` | Yes | - | Destination path for the filtered JPEG. |
| `maxSide` | `Int` | No | `0` (full) | Downsamples image before filtering if > 0 (e.g. 200 for thumbnail, 1600 for preview). |

#### Return Value:
- `outPath` on success.

#### Error Codes:
- `INVALID_ARGS`: Missing required arguments.
- `FILTER_FAILED`: Filter execution failed.

---

### `rotateLeft`
Rotates an image 90 degrees counter-clockwise and writes the result. (Used primarily for session-list page rotation).

#### Arguments:
| Key | Type | Required | Description |
|---|---|---|---|
| `path` | `String` | Yes | Absolute path to input image. |
| `outPath` | `String` | Yes | Absolute path to output image. |

#### Return Value:
- `outPath` on success.

#### Error Codes:
- `INVALID_ARGS`: Missing arguments.
- `READ_FAILED`: Failed to read input image.
- `WRITE_FAILED`: Failed to write output image.
- `ROTATE_ERROR`: Processing exception.

---

## 3. Filter Specifications & Final Reference Constants

| Filter Name | Aliases | Pipeline / Formula | Reference Constants |
|---|---|---|---|
| `original` | - | Passthrough clone / copy | - |
| `flatten` (Internal) | - | Background illumination compensation: `src / bg * 255.0` | Target downscale longer side 400px; Morphological Dilation with 7x7 Ellipse kernel; Median Blur 21x21; Upscale `INTER_LINEAR` to original size; `Core.divide(src, fullBg, 255.0)`. |
| `lighten` | `color` | Gamma curve with mild contrast expansion | `gamma = 0.7`, `contrastFactor = 1.08`. Formula: `((val^0.7 - 0.5) * 1.08 + 0.5) * 255.0`. |
| `enhance` | `document` | `flatten` -> Levels LUT -> Unsharp Mask | **Levels**: `black = 35`, `white = 225`, `gamma = 1.1`. Formula: `255 * ((v - 35) / (225 - 35))^1.1`.<br>**Unsharp Mask**: Gaussian Blur `sigma = 2.0`, Weights: `1.6 * leveled - 0.6 * blurred`. |
| `gray` | `grayscale` | `flatten` -> Grayscale -> Levels LUT -> BGR | **Levels**: `black = 40`, `white = 220`, `invGamma = 1.0 / 1.1`. Formula: `255 * ((v - 40) / (220 - 40))^(1/1.1)`. Always converted back to 3-channel. |
| `eco` | `blackwhite` | `flatten` -> Grayscale -> Adaptive Gaussian Threshold -> BGR | `blockSize = max(3, (min(width, height) / 30) \| 1)`. `C = 12.0`. Type: `ADAPTIVE_THRESH_GAUSSIAN_C`, `THRESH_BINARY`. Output converted to 3-channel. |
| `no_handwriting` | `nohandwriting` | `enhance` -> Colored ink HSV mask -> Dilate 3x3 (2 iterations) -> Paint white | **HSV Mask Range**: `H: [0..180]`, `S: [70..255]`, `V: [40..255]`. Dilation: 3x3 Rectangular kernel, 2 iterations. `setTo(Scalar(255, 255, 255), mask)`. |

---

## 4. Native Camera UI & Interaction Specification

### Viewport & Aspect Ratio
- Centered 3:4 aspect ratio container.
- Normalized coordinates `[0.0, 1.0]` directly map to the 3:4 preview area and upright capture sensor output.

### Controls & Arabic Strings
- **Mode Toggle Button**:
  - Single Mode: `"مفرد"`
  - Batch Mode: `"دفعة"`
- **Done Button (Batch Mode)**:
  - Text: `"تم (N)"` where `N` is the number of captured pages.
  - Hidden when `N == 0`.
- **Torch Toggle Button**:
  - Toggles camera torch/flashlight on and off.
- **Gallery Import Button (Bottom Bar Start)**:
  - Circular icon button (`48x48 dp`) at the start side of the bottom bar (`marginStart = 24dp`).
  - **Single Mode (`batch == false`)**: Opens single-image picker (`GetContent` on Android / `PHPickerViewController(selectionLimit: 1)` on iOS), copies to `destDir/raw_<uuid>.jpg`, detects quad corners (or 5% inset fallback), and immediately returns the result.
  - **Batch Mode (`batch == true`)**: Opens multi-image picker (`GetMultipleContents` on Android / `PHPickerViewController(selectionLimit: 0)` on iOS), imports all selected images, runs quad detection on each, appends to the batch list, and updates the `"تم (N)"` button.
- **Close Button**:
  - If batch count == 0: Cancels and returns `null`.
  - If batch count > 0: Displays confirmation alert dialog:
    - **Title**: `"صفحات غير محفوظة"`
    - **Message**: `"لديك N صفحة ممسوحة. هل تريد حفظها ومتابعة الجلسة أم إلغاء الكل؟"`
    - **Positive Button**: `"حفظ ومتابعة"` -> Finishes with batch items.
    - **Negative Button**: `"إلغاء الكل"` -> Deletes all batch raw files from disk and returns `null`.
    - **Neutral Button**: `"البقاء في الكاميرا"` -> Dismisses dialog and stays in camera.

### Detection & Smoothing
- Candidate quad area must be between **15% and 97%** of the frame area.
- Convex quads only.
- Temporal smoothing: LERP factor `0.5`.
- Reset immediately if any corner jumps `> 15%` of normalized frame dimension.
- Missed frame threshold: Hide polygon overlay and clear previous quad tracking after **> 5** consecutive missed frames.
- Shutter debounce: **600 ms**.
- Fallback when no quad is detected: Return a 5% inset rectangle:
  `[0.05, 0.05, 0.95, 0.05, 0.95, 0.95, 0.05, 0.95]`.

---

## 5. Dart-Side Assumptions & Cross-Platform Nuances

1. **Path Storage**:
   - `LocalDocumentStore` persists file paths relative to the application documents directory (e.g., `scans/...`).
   - Absolute paths are resolved dynamically at runtime using `path_provider.getApplicationDocumentsDirectory()`, which is critical for iOS where the sandbox UUID changes between builds/reinstalls.
2. **Permission Handling**:
   - Dart's `PermissionRequestCoordinator` requests `Permission.camera` before calling `startScan`.
   - On iOS, denied permissions report `PermissionStatus.permanentlyDenied`, triggering a dialog offering `openAppSettings()`.
3. **EXIF Orientation**:
   - `PdfBuilderService` relies on JPEG files being upright with EXIF orientation 1 to enable raw JPEG passthrough into PDF pages without re-encoding.
