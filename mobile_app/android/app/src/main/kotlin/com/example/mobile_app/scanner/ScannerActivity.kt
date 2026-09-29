package com.example.mobile_app.scanner

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageButton
import androidx.activity.ComponentActivity
import androidx.camera.core.AspectRatio
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import org.opencv.android.OpenCVLoader
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfInt
import org.opencv.core.Point
import org.opencv.core.Size
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc
import java.io.File
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.hypot

class ScannerActivity : ComponentActivity() {

    companion object {
        private const val TAG = "ScannerActivity"
        const val EXTRA_DEST_DIR = "extra_dest_dir"
        const val RESULT_PATH = "result_path"
        const val RESULT_CORNERS = "result_corners" // DoubleArray of 8 normalized coords
        const val RESULT_WIDTH = "result_width"
        const val RESULT_HEIGHT = "result_height"
    }

    private lateinit var cameraExecutor: ExecutorService
    private var camera: Camera? = null
    private var imageCapture: ImageCapture? = null
    private var previewView: PreviewView? = null
    private var overlayView: PolygonOverlayView? = null
    private var flashButton: ImageButton? = null

    private var destinationDir: String? = null
    private var isTorchOn = false
    private var isCapturing = false
    private var lastShutterTime = 0L

    // Live quad tracking state
    @Volatile
    private var latestNormalizedQuad: List<Point>? = null
    private var previousQuad: List<Point>? = null
    private var missedFrameCount = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (!OpenCVLoader.initLocal()) {
            Log.e(TAG, "OpenCVLoader.initLocal() failed")
        }

        destinationDir = intent.getStringExtra(EXTRA_DEST_DIR) ?: cacheDir.absolutePath
        cameraExecutor = Executors.newSingleThreadExecutor()

        buildUi()
        startCamera()
    }

    override fun onDestroy() {
        super.onDestroy()
        cameraExecutor.shutdown()
    }

    private fun buildUi() {
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        // AspectFrameLayout maintaining 3:4 portrait ratio (4:3 camera sensor)
        val aspectContainer = AspectRatioFrameLayout(this, 3.0f / 4.0f).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            )
        }

        previewView = PreviewView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
        aspectContainer.addView(previewView)

        overlayView = PolygonOverlayView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        aspectContainer.addView(overlayView)
        root.addView(aspectContainer)

        // Top control bar
        val topBar = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(72),
                Gravity.TOP
            )
            setPadding(dp(16), dp(16), dp(16), dp(16))
        }

        val closeButton = ImageButton(this).apply {
            layoutParams = FrameLayout.LayoutParams(dp(44), dp(44), Gravity.START or Gravity.CENTER_VERTICAL)
            setBackgroundColor(Color.TRANSPARENT)
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            setColorFilter(Color.WHITE)
            setOnClickListener {
                setResult(Activity.RESULT_CANCELED)
                finish()
            }
        }
        topBar.addView(closeButton)

        flashButton = ImageButton(this).apply {
            layoutParams = FrameLayout.LayoutParams(dp(44), dp(44), Gravity.END or Gravity.CENTER_VERTICAL)
            setBackgroundColor(Color.TRANSPARENT)
            setImageResource(android.R.drawable.ic_menu_camera)
            setColorFilter(Color.WHITE)
            setOnClickListener { toggleFlash() }
        }
        topBar.addView(flashButton)
        root.addView(topBar)

        // Bottom control bar with shutter button
        val bottomBar = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(120),
                Gravity.BOTTOM
            )
            setBackgroundColor(Color.parseColor("#44000000"))
        }

        val shutterButton = View(this).apply {
            val size = dp(74)
            layoutParams = FrameLayout.LayoutParams(size, size, Gravity.CENTER)
            val outerBorder = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.OVAL
                setColor(Color.WHITE)
                setStroke(dp(4), Color.parseColor("#00E676"))
            }
            background = outerBorder
            setOnClickListener { takeShutterPicture() }
        }
        bottomBar.addView(shutterButton)
        root.addView(bottomBar)

        setContentView(root)
    }

    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()

            val preview = Preview.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .build()
                .also {
                    it.setSurfaceProvider(previewView?.surfaceProvider)
                }

            imageCapture = ImageCapture.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                .setJpegQuality(95)
                .build()

            val imageAnalysis = ImageAnalysis.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                .build()

            imageAnalysis.setAnalyzer(cameraExecutor) { imageProxy ->
                analyzePreviewFrame(imageProxy)
            }

            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

            try {
                cameraProvider.unbindAll()
                camera = cameraProvider.bindToLifecycle(
                    this,
                    cameraSelector,
                    preview,
                    imageCapture,
                    imageAnalysis
                )
            } catch (exc: Exception) {
                Log.e(TAG, "Camera binding failed", exc)
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun toggleFlash() {
        val cam = camera ?: return
        if (!cam.cameraInfo.hasFlashUnit()) return

        isTorchOn = !isTorchOn
        cam.cameraControl.enableTorch(isTorchOn)
        flashButton?.setColorFilter(if (isTorchOn) Color.parseColor("#FFEB3B") else Color.WHITE)
    }

    @SuppressLint("UnsafeOptInUsageError")
    private fun analyzePreviewFrame(imageProxy: ImageProxy) {
        try {
            val yPlane = imageProxy.planes[0]
            val yBuffer = yPlane.buffer
            val rowStride = yPlane.rowStride
            val pixelStride = yPlane.pixelStride
            val width = imageProxy.width
            val height = imageProxy.height

            // Create grayscale Mat from Y-plane
            val yMat = if (rowStride == width && pixelStride == 1) {
                val bytes = ByteArray(yBuffer.remaining())
                yBuffer.get(bytes)
                Mat(height, width, CvType.CV_8UC1).apply {
                    put(0, 0, bytes)
                }
            } else {
                val fullMat = Mat(height, rowStride, CvType.CV_8UC1)
                val bytes = ByteArray(yBuffer.remaining())
                yBuffer.get(bytes)
                fullMat.put(0, 0, bytes)
                val sub = fullMat.submat(0, height, 0, width)
                val result = Mat()
                sub.copyTo(result)
                fullMat.release()
                sub.release()
                result
            }

            // Rotate according to CameraX image rotation
            val rotationDegrees = imageProxy.imageInfo.rotationDegrees
            val rotated = Mat()
            when (rotationDegrees) {
                90 -> Core.rotate(yMat, rotated, Core.ROTATE_90_CLOCKWISE)
                180 -> Core.rotate(yMat, rotated, Core.ROTATE_180)
                270 -> Core.rotate(yMat, rotated, Core.ROTATE_90_COUNTERCLOCKWISE)
                else -> yMat.copyTo(rotated)
            }
            yMat.release()

            val detectedQuad = DocumentDetector.findQuad(rotated)
            val rotW = rotated.cols().toDouble()
            val rotH = rotated.rows().toDouble()
            rotated.release()

            if (detectedQuad != null) {
                // Normalize points to [0.0, 1.0]
                val normalized = detectedQuad.map { Point(it.x / rotW, it.y / rotH) }
                val smoothed = smoothQuad(normalized)
                latestNormalizedQuad = smoothed
                missedFrameCount = 0

                runOnUiThread {
                    overlayView?.setPolygon(smoothed)
                }
            } else {
                missedFrameCount++
                if (missedFrameCount > 5) {
                    latestNormalizedQuad = null
                    runOnUiThread {
                        overlayView?.setPolygon(null)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error analyzing preview frame", e)
        } finally {
            imageProxy.close()
        }
    }

    /**
     * Temporal smoothing with LERP 0.5 and >15% jump reset.
     */
    private fun smoothQuad(newQuad: List<Point>): List<Point> {
        val prev = previousQuad
        if (prev == null || prev.size != 4) {
            previousQuad = newQuad
            return newQuad
        }

        // Check if any corner jumped > 15% (0.15 normalized distance)
        var maxJump = 0.0
        for (i in 0..3) {
            val dist = hypot(newQuad[i].x - prev[i].x, newQuad[i].y - prev[i].y)
            if (dist > maxJump) maxJump = dist
        }

        if (maxJump > 0.15) {
            // Document moved significantly: reset immediately to new coordinates
            previousQuad = newQuad
            return newQuad
        }

        val smoothed = ArrayList<Point>(4)
        for (i in 0..3) {
            smoothed.add(
                Point(
                    prev[i].x * 0.5 + newQuad[i].x * 0.5,
                    prev[i].y * 0.5 + newQuad[i].y * 0.5
                )
            )
        }
        previousQuad = smoothed
        return smoothed
    }

    private fun takeShutterPicture() {
        val now = SystemClock.elapsedRealtime()
        if (isCapturing || now - lastShutterTime < 1000) {
            return // Shutter debounce
        }
        isCapturing = true
        lastShutterTime = now

        val capture = imageCapture ?: run {
            isCapturing = false
            return
        }

        // Snapshot current stable live quad
        val liveQuad = latestNormalizedQuad

        capture.takePicture(
            cameraExecutor,
            object : ImageCapture.OnImageCapturedCallback() {
                override fun onCaptureSuccess(imageProxy: ImageProxy) {
                    processCapturedPhoto(imageProxy, liveQuad)
                }

                override fun onError(exception: ImageCaptureException) {
                    Log.e(TAG, "Capture failed: ${exception.message}", exception)
                    isCapturing = false
                }
            }
        )
    }

    @SuppressLint("UnsafeOptInUsageError")
    private fun processCapturedPhoto(imageProxy: ImageProxy, liveNormalizedQuad: List<Point>?) {
        try {
            val rotationDegrees = imageProxy.imageInfo.rotationDegrees
            val plane = imageProxy.planes[0]
            val buffer = plane.buffer
            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)

            val rawMat = Mat(1, bytes.size, CvType.CV_8UC1)
            rawMat.put(0, 0, bytes)
            val decoded = Imgcodecs.imdecode(rawMat, Imgcodecs.IMREAD_COLOR)
            rawMat.release()

            if (decoded.empty()) {
                Log.e(TAG, "Failed to decode captured photo")
                isCapturing = false
                return
            }

            // Rotate manually by rotationDegrees
            val oriented = Mat()
            when (rotationDegrees) {
                90 -> Core.rotate(decoded, oriented, Core.ROTATE_90_CLOCKWISE)
                180 -> Core.rotate(decoded, oriented, Core.ROTATE_180)
                270 -> Core.rotate(decoded, oriented, Core.ROTATE_90_COUNTERCLOCKWISE)
                else -> decoded.copyTo(oriented)
            }
            decoded.release()

            val photoW = oriented.cols().toDouble()
            val photoH = oriented.rows().toDouble()

            // Resolve final corners (normalized 0.0..1.0)
            val finalNormalizedCorners: List<Point> = if (liveNormalizedQuad != null) {
                liveNormalizedQuad
            } else {
                // If live quad was absent, run detector once on downscaled photo
                val gray = Mat()
                Imgproc.cvtColor(oriented, gray, Imgproc.COLOR_BGR2GRAY)
                val detected = DocumentDetector.findQuad(gray)
                gray.release()

                if (detected != null) {
                    detected.map { Point(it.x / photoW, it.y / photoH) }
                } else {
                    // Fallback to 5% inset rectangle
                    listOf(
                        Point(0.05, 0.05),
                        Point(0.95, 0.05),
                        Point(0.95, 0.95),
                        Point(0.05, 0.95)
                    )
                }
            }

            // Write original oriented JPEG directly into destination directory
            val destFolder = File(destinationDir!!)
            destFolder.mkdirs()
            val fileName = "raw_${UUID.randomUUID()}.jpg"
            val outputFile = File(destFolder, fileName)

            val writeParams = MatOfInt(Imgcodecs.IMWRITE_JPEG_QUALITY, 95)
            Imgcodecs.imwrite(outputFile.absolutePath, oriented, writeParams)
            writeParams.release()
            oriented.release()

            // Format corners array [tl.x, tl.y, tr.x, tr.y, br.x, br.y, bl.x, bl.y]
            val cornersArray = DoubleArray(8)
            cornersArray[0] = finalNormalizedCorners[0].x
            cornersArray[1] = finalNormalizedCorners[0].y
            cornersArray[2] = finalNormalizedCorners[1].x
            cornersArray[3] = finalNormalizedCorners[1].y
            cornersArray[4] = finalNormalizedCorners[2].x
            cornersArray[5] = finalNormalizedCorners[2].y
            cornersArray[6] = finalNormalizedCorners[3].x
            cornersArray[7] = finalNormalizedCorners[3].y

            val resultIntent = Intent().apply {
                putExtra(RESULT_PATH, outputFile.absolutePath)
                putExtra(RESULT_CORNERS, cornersArray)
                putExtra(RESULT_WIDTH, photoW.toInt())
                putExtra(RESULT_HEIGHT, photoH.toInt())
            }

            runOnUiThread {
                setResult(Activity.RESULT_OK, resultIntent)
                finish()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing captured photo", e)
            isCapturing = false
        } finally {
            imageProxy.close()
        }
    }

    private fun dp(value: Int): Int {
        val density = resources.displayMetrics.density
        return (value * density).toInt()
    }
}

/**
 * Custom FrameLayout that enforces a strict target aspect ratio (width / height).
 */
class AspectRatioFrameLayout(
    context: android.content.Context,
    private val targetRatio: Float
) : FrameLayout(context) {

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val originalWidth = MeasureSpec.getSize(widthMeasureSpec)
        val originalHeight = MeasureSpec.getSize(heightMeasureSpec)

        var finalWidth = originalWidth
        var finalHeight = originalHeight

        if (originalWidth > 0 && originalHeight > 0) {
            val currentRatio = originalWidth.toFloat() / originalHeight.toFloat()
            if (currentRatio > targetRatio) {
                // Too wide: constrain width
                finalWidth = (originalHeight * targetRatio).toInt()
            } else {
                // Too tall: constrain height
                finalHeight = (originalWidth / targetRatio).toInt()
            }
        }

        val exactWidth = MeasureSpec.makeMeasureSpec(finalWidth, MeasureSpec.EXACTLY)
        val exactHeight = MeasureSpec.makeMeasureSpec(finalHeight, MeasureSpec.EXACTLY)
        super.onMeasure(exactWidth, exactHeight)
    }
}

/**
 * Overlay view that draws a translucent polygon and smooth borders over detected document quad.
 */
class PolygonOverlayView(context: android.content.Context) : View(context) {

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = Color.parseColor("#3300E676") // Translucent light green
    }

    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = Color.parseColor("#FF00E676") // Vibrant green
        strokeWidth = 3f * resources.displayMetrics.density
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    private var normalizedPoints: List<Point>? = null
    private val path = Path()

    fun setPolygon(pts: List<Point>?) {
        normalizedPoints = pts
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val pts = normalizedPoints ?: return
        if (pts.size != 4) return

        val w = width.toFloat()
        val h = height.toFloat()

        path.reset()
        path.moveTo((pts[0].x * w).toFloat(), (pts[0].y * h).toFloat())
        path.lineTo((pts[1].x * w).toFloat(), (pts[1].y * h).toFloat())
        path.lineTo((pts[2].x * w).toFloat(), (pts[2].y * h).toFloat())
        path.lineTo((pts[3].x * w).toFloat(), (pts[3].y * h).toFloat())
        path.close()

        canvas.drawPath(path, fillPaint)
        canvas.drawPath(path, strokePaint)
    }
}
