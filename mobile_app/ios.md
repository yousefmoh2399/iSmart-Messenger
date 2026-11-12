CONTEXT
Flutter app (repo iSmart-Messenger, mobile_app), branch feature/native-scanner. Android is finished (Phases 1-3 + polish): a native CameraX + OpenCV scanner behind MethodChannel "ismart/doc_scanner"; Dart side in lib/features/scanner (NativeScannerBridge, ScanReviewScreen, QuadCropEditor, ScannerSessionScreen, LocalDocumentStore with paths relative to the documents directory). iOS never had a working scanner: the old google_mlkit_document_scanner returned NotImplemented on iOS and has been removed. Implement the iOS half with the SAME contract, so the Dart code needs no platform branches. I have a Mac and a real iPhone, so you can build and run for real. The iOS Simulator has no camera, so scanner testing needs the physical device.

GATING
Do STEP 0 and STEP 1 only, then STOP and report. Do not start STEP 2 until I confirm that the Android real-device test is accepted, because the contract and the filter constants may still change. After STEP 6, STOP again for the device session (STEP 7).

GENERAL RULES
- The Android implementation is the source of truth. Read native_scanner_bridge.dart, MainActivity.kt (channel handler), ScannerActivity.kt (extras and results, single AND batch mode, back/close behavior with pending pages), DocumentDetector.kt and ImageFilters.kt. Write docs/native_scanner_contract.md: method names, argument names/types (including warp's optional maxSide and quarterTurns), result shapes for single and batch, error codes, coordinate conventions, filter names, file formats, and the FINAL Android filter constants. Mirror it exactly. Report anything Dart relies on that is Android-specific.
- Never present estimates as measurements; label whatever you cannot run "UNVERIFIED".
- One commit per step. After each step: flutter analyze and `flutter build ios --debug --no-codesign` must pass, and `flutter build apk --debug` must still pass. Do not change Android behavior. If iOS needs a contract change, propose it first, because Android must change with it.
- Arabic UI strings must match Android's.

STEP 0 — Baseline (report before changing code)
flutter --version, flutter doctor -v, xcodebuild -version, pod --version; the iOS deployment target (Podfile + Runner project); the highest MinimumOSVersion among the pods in Podfile.lock; the existing permission setup (Info.plist keys, Podfile PERMISSION_* macros for permission_handler); AppDelegate.swift and any existing channels. Run flutter pub get, `cd ios && pod install`, and `flutter build ios --debug --no-codesign`. Record whether iOS builds BEFORE any change, and any pre-existing warnings.

STEP 1 — Project setup
1. Raise the deployment target to 15.0 (Podfile platform, Runner IPHONEOS_DEPLOYMENT_TARGET, any pod override) unless a dependency needs higher (report). Reason: VNDetectDocumentSegmentationRequest needs iOS 15 and CIColorThreshold needs iOS 14.
2. Info.plist: add Arabic + English NSCameraUsageDescription (photo-library keys only if some existing feature really needs them). In the Podfile post_install make sure PERMISSION_CAMERA=1 is set for permission_handler while keeping the existing macros.
3. Put ALL Swift code in a local Flutter plugin package: packages/doc_scanner_ios (platforms: ios only; the plugin class registers "ismart/doc_scanner" in register(with:)); add it to pubspec.yaml as a path dependency. Podspec: iOS 15.0, swift_version, frameworks AVFoundation, Vision, CoreImage, CoreMedia, ImageIO, UIKit, Metal. Avoid hand-editing project.pbxproj. Verify the Android build ignores the plugin.
4. Create a stub channel handler that answers notImplemented and confirm the app builds and launches on the iOS build path. Then STOP and report (GATING).

STEP 2 — Camera + live detection (ScannerViewController)
- Present .fullScreen from the topmost view controller; portrait only (override supportedInterfaceOrientations, shouldAutorotate false).
- 3:4 container view centered in the screen; AVCaptureVideoPreviewLayer (resizeAspectFill) and a CAShapeLayer overlay with the same frame, so normalized coordinates map exactly (same idea as Android's AspectRatioFrameLayout). Top bar: close, torch toggle, single/batch toggle ("مفرد" / "دفعة"). Bottom: shutter (white with a green #00E676 ring) and, in batch mode, the "تم (N)" button. Mirror Android's strings and behavior.
- AVCaptureSession with preset .photo, back wide-angle camera, continuous autofocus and exposure. startRunning/stopRunning on a dedicated serial queue, never on the main thread. Handle AVCaptureSessionWasInterrupted / InterruptionEnded and app backgrounding.
- AVCaptureVideoDataOutput: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, alwaysDiscardsLateVideoFrames = true, serial delegate queue. Do not rotate buffers; pass orientation .right to the Vision handler.
- Per frame: VNDetectDocumentSegmentationRequest via VNImageRequestHandler(cvPixelBuffer:orientation: .right). Drop frames while a request is in flight. Convert Vision's bottom-left origin to top-left (y = 1 - y). Accept only convex quads with area between 15% and 97% of the frame (shoelace formula). Order TL,TR,BR,BL with the same sum / (y-x) method as Android. Smoothing identical to Android: lerp 0.5, reset if any corner jumps >15%, tolerate 5 missed frames, then hide AND clear the previous quad.
- Log with tag "DocScan" (os_log + print): the average analyzer time per 30 frames. If it exceeds 30 ms, analyze every 2nd frame and report.

STEP 3 — Capture (single + batch)
- AVCapturePhotoOutput, JPEG. Set maxPhotoQualityPrioritization = .speed on the output AND photoQualityPrioritization = .speed on the settings; flash off (the torch handles light). Set the photo connection to portrait (videoOrientation .portrait, or videoRotationAngle = 90 on iOS 17+) so the file is upright.
- In didFinishProcessingPhoto write photo.fileDataRepresentation() straight to destDir/raw_<uuid>.jpg (no decode/re-encode). Read the real orientation with ImageIO and return UPRIGHT width/height (swap for EXIF orientations 5-8). If a file is not upright and carries no orientation tag, fix it with a lossless metadata rewrite (CGImageDestinationCopyImageSource).
- Corners: the last stable live quad snapshotted AT TAP TIME; else one Vision pass on a ~800 px thumbnail of the captured file (kCGImageSourceCreateThumbnailWithTransform); else a 5% inset rectangle. Return exactly the map shape Android returns.
- Shutter debounce 600 ms with a thread-safe isCapturing flag. Single mode: dismiss immediately after the file is written, then reply. Batch mode: stay open, brief visual feedback, thumbnail counter, and "تم (N)" returns the list in Android's exact shape. Back/close with pending pages shows the same Arabic confirmation as Android (save and continue / discard all, deleting the raw files / stay).
- Exactly one pending Flutter result, never replied twice or leaked. Return null on cancel, permission denied, session interruption or app backgrounded (mirror Android). Log tap -> file written -> reply timings.

STEP 4 — warp / rotateLeft
- warp(path, corners, outPath, maxSide?, quarterTurns?): load with the orientation applied. When maxSide is set and the source is at least 2x larger, decode reduced through an ImageIO thumbnail (cheap preview); never reduce when the source is already close to maxSide. Convert normalized top-left corners to Core Image coordinates (origin bottom-left), shrink 0.5% toward the centroid, apply CIPerspectiveCorrection, and make the output size follow Android's edge-length formula (scaled for maxSide; crop/scale so the extent starts at 0,0 and has exactly that size). Apply quarterTurns (counter-clockwise) BEFORE the single JPEG write. Write JPEG q0.95 in sRGB. Final page files must be upright with EXIF orientation 1 (PdfBuilder's fast path depends on it).
- rotateLeft = oriented(.left) + write.
- All work off the main thread, native concurrency limited to 2 (semaphore), replies on the main thread.

STEP 5 — Filters (Core Image) with visual parity to Android
- ONE shared CIContext (Metal-backed), created once, with options [.workingColorSpace: NSNull(), .workingFormat: CIFormat.RGBAh, .cacheIntermediates: false]. NSNull is essential: by default Core Image works in linear light and would make the division and levels look different from OpenCV's gamma-space math. Every filter runs inside autoreleasepool.
- Read the FINAL constants from ImageFilters.kt and mirror them. Names: original | lighten | enhance | gray | eco | no_handwriting.
- flatten: downscale to ~400 px, CIMorphologyMaximum (radius ~3), a large CIGaussianBlur as the stand-in for medianBlur 21 (clampedToExtent, tune visually), upscale bilinearly to full size, then divide the image by the background. Verify CIDivideBlendMode's operand order empirically (paper must become white, ink must stay dark). If you need a custom CIColorKernel, tell me first, because it needs build-flag changes.
- enhance = flatten -> levels (CIColorMatrix, scale 255/190 and bias -35/190 per channel, then CIColorClamp 0..1) -> CIGammaAdjust with the same gamma semantics as Android's LUT -> CIUnsharpMask (Android: sigma 2 px, weights 1.6/-0.6 => intensity 0.6; tune the radius visually).
- lighten and gray as in Android (gray = flatten -> CIColorControls saturation 0 -> levels).
- eco: mirror OpenCV's adaptive threshold: gray - gaussianBlur(gray, sigma = 0.3*((blockSize-1)/2 - 1) + 0.8, blockSize = (min(w,h)/30)|1) + 12/255, then CIColorThreshold at the matching midpoint. Do NOT use a single global threshold.
- no_handwriting: enhance -> a mask of saturated pixels (32^3 CIColorCube outputting white where S>70/255 and V>40/255, black elsewhere) -> CIMorphologyMaximum radius ~2 -> composite white over the image (verify whether CIBlendWithMask reads the mask's luminance or its alpha). Colored stamps also disappear (same limitation as Android).
- Parity harness (kDebugMode only): a temporary screen or command that runs all 6 filters on the sample images I supply, writes the outputs to a folder, and a script that builds side-by-side contact sheets against my Android outputs. Tune the constants until they look alike. If Core Image cannot reach acceptable parity or speed, STOP and propose an OpenCV Objective-C++ wrapper instead of forcing it.

STEP 6 — Dart-side checks (shared code)
- No Platform.isAndroid / Platform.isIOS branches in the scanner code. iOS permission flow through permission_handler: after a denial iOS reports permanently denied -> offer openAppSettings.
- Confirm drafts store paths relative to the documents directory (the iOS container UUID changes on update/reinstall) and that the migration path works.
- Confirm the PDF fast path accepts the iOS-produced JPEGs (EXIF orientation 1, <=2048 px).
- Confirm nothing in the scanner flow needs the network.
Then STOP (device session).

STEP 7 — Real device
- flutter devices; I will connect the iPhone (Developer Mode on, trusted). Guide me through the Xcode signing (personal team is OK, unique bundle id, trust the developer certificate on the phone) and `flutter run --release -d <id>`. Logs through `flutter logs` and the Xcode/Console output filtered by "DocScan".
- You cannot operate the phone: give me a manual checklist and wait for my logs. Every number in your final report must come from those logs or be marked UNVERIFIED.

BUDGET / ACCEPTANCE (real iPhone)
Live analysis <=30 ms/frame; tap -> result screen <=300 ms; warp preview <=150 ms; filter switch <=200 ms; thumbnail <=50 ms. Tests: white paper on a dark desk, on a white desk, a folded page, a 30-degree tilt, low light, a page cut by the frame, rapid shutter taps, airplane mode, permission denied -> null, an incoming call or app switch during capture, a batch of 25 pages without memory warnings, back/close with pending pages, rotate then re-crop keeps the orientation, draft restore after killing the app, PDF page orientation.

DELIVERABLES
Files changed per step, docs/native_scanner_contract.md, the parity contact sheets, the size of Runner.app from `flutter build ios --release --no-codesign` versus the baseline, and an honest list of everything UNVERIFIED.