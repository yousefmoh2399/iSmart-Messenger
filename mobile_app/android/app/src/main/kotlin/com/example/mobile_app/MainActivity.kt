package com.example.mobile_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.app.Person
import androidx.core.content.FileProvider
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import android.app.Activity
import com.example.mobile_app.scanner.DocumentDetector
import com.example.mobile_app.scanner.ImageFilters
import com.example.mobile_app.scanner.ScannerActivity
import android.os.SystemClock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.opencv.android.OpenCVLoader
import org.opencv.core.Core
import org.opencv.core.Mat
import org.opencv.core.MatOfInt
import org.opencv.core.Point
import org.opencv.imgcodecs.Imgcodecs
import android.graphics.BitmapFactory
import kotlin.math.max

class MainActivity : FlutterActivity() {
    private val installerChannel = "app.installer"
    private val shareChannel = "app.share_receiver"
    private val docScannerChannel = "ismart/doc_scanner"
    private val REQUEST_CODE_SCANNER = 0x534341
    private var pendingScannerResult: MethodChannel.Result? = null
    private val mainScope = CoroutineScope(Dispatchers.Main)
    private val nativeOpSemaphore = java.util.concurrent.Semaphore(2)
    private var shareMethodChannel: MethodChannel? = null
    private var pendingShare: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        captureShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureShareIntent(intent)
    }

    private fun captureShareIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND && intent?.action != Intent.ACTION_SEND_MULTIPLE) return
        val paths = mutableListOf<String>()
        val streams: List<Uri> = if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
        } else {
            listOfNotNull(intent.getParcelableExtra(Intent.EXTRA_STREAM))
        }
        streams.forEachIndexed { index, uri ->
            try {
                val extension = contentResolver.getType(uri)?.substringAfterLast('/') ?: "jpg"
                val target = File(cacheDir, "shared_${System.currentTimeMillis()}_${index}.$extension")
                contentResolver.openInputStream(uri)?.use { input -> target.outputStream().use { output -> input.copyTo(output) } }
                if (target.exists()) paths.add(target.absolutePath)
            } catch (_: Exception) { }
        }
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: ""
        val conversationId = intent.getStringExtra("directConversationId")
            ?: intent.getStringExtra(Intent.EXTRA_SHORTCUT_ID)?.removePrefix("chat_")
            ?: ""
        if (paths.isEmpty() && text.isBlank()) return
        pendingShare = mapOf("text" to text, "paths" to paths, "conversationId" to conversationId)
        shareMethodChannel?.invokeMethod("sharedContent", pendingShare)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallUnknownApps" -> {
                        val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        }
                        result.success(allowed)
                    }
                    "openUnknownAppsSettings" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                val intent = Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName"),
                                )
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                            } else {
                                val intent = Intent(Settings.ACTION_SECURITY_SETTINGS)
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_SETTINGS_FAILED", e.message, null)
                        }
                    }
                    "installApk" -> {
                        val apkPath = call.argument<String>("apkPath")
                        if (apkPath.isNullOrBlank()) {
                            result.error("INVALID_PATH", "apkPath is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val apkFile = File(apkPath)
                            if (!apkFile.exists()) {
                                result.error("FILE_NOT_FOUND", "APK file not found", null)
                                return@setMethodCallHandler
                            }
                            val apkUri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                apkFile,
                            )
                            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(
                                    apkUri,
                                    "application/vnd.android.package-archive",
                                )
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(installIntent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_INTENT_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        shareMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannel)
        shareMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedContent" -> { result.success(pendingShare); pendingShare = null }
                "updateDirectShareTargets" -> {
                    val rawTargets = call.argument<List<Map<String, Any?>>>("targets") ?: emptyList()
                    val shortcuts = rawTargets.take(8).mapIndexed { index, target ->
                        val id = target["id"]?.toString() ?: ""
                        val label = target["label"]?.toString()?.take(25) ?: "Chat"
                        ShortcutInfoCompat.Builder(this, "chat_$id")
                            .setShortLabel(label)
                            .setLongLabel(label)
                            .setIcon(IconCompat.createWithResource(this, applicationInfo.icon))
                            .setPerson(
                                Person.Builder()
                                    .setName(label)
                                    .setKey(id)
                                    .build()
                            )
                            .setCategories(setOf(
                                "com.example.mobile_app.share.TEXT",
                                "com.example.mobile_app.share.IMAGE",
                            ))
                            .setRank(index)
                            .setLongLived(true)
                            .setIsConversation()
                            .setIntent(
                                Intent(this, MainActivity::class.java)
                                    .setAction(Intent.ACTION_SEND)
                                    .putExtra("directConversationId", id)
                            )
                            .build()
                    }
                    ShortcutManagerCompat.setDynamicShortcuts(this, shortcuts)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        if (!OpenCVLoader.initLocal()) {
            android.util.Log.e("MainActivity", "OpenCV init failed")
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, docScannerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startScan" -> {
                        if (pendingScannerResult != null) {
                            result.error("SCANNER_BUSY", "A scan is already in progress", null)
                            return@setMethodCallHandler
                        }
                        pendingScannerResult = result
                        val destDir = call.argument<String>("destDir")
                        val batch = call.argument<Boolean>("batch") ?: false
                        try {
                            val intent = Intent(this, ScannerActivity::class.java).apply {
                                if (!destDir.isNullOrBlank()) {
                                    putExtra(ScannerActivity.EXTRA_DEST_DIR, destDir)
                                }
                                putExtra(ScannerActivity.EXTRA_BATCH_MODE, batch)
                            }
                            startActivityForResult(intent, REQUEST_CODE_SCANNER)
                        } catch (e: Exception) {
                            pendingScannerResult = null
                            result.error("LAUNCH_FAILED", "Failed to launch ScannerActivity: ${e.message}", null)
                        }
                    }
                    "warp" -> {
                        val path = call.argument<String>("path")
                        val rawCorners = call.argument<List<Double>>("corners")
                        val outPath = call.argument<String>("outPath")
                        val maxSide = call.argument<Int>("maxSide") ?: 0
                        val quarterTurns = call.argument<Int>("quarterTurns") ?: 0
                        if (path.isNullOrBlank() || rawCorners == null || rawCorners.size != 8 || outPath.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "path, corners (8 items), and outPath are required", null)
                            return@setMethodCallHandler
                        }
                        mainScope.launch(Dispatchers.Default) {
                            nativeOpSemaphore.acquire()
                            val warpStart = SystemClock.elapsedRealtime()
                            try {
                                var useReduced = false
                                if (maxSide > 0) {
                                    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                                    BitmapFactory.decodeFile(path, options)
                                    val longerSide = max(options.outWidth, options.outHeight)
                                    if (longerSide >= 2 * maxSide) {
                                        useReduced = true
                                    }
                                }
                                val readFlags = if (useReduced) Imgcodecs.IMREAD_REDUCED_COLOR_2 else Imgcodecs.IMREAD_COLOR
                                val src = Imgcodecs.imread(path, readFlags)
                                if (src.empty()) {
                                    withContext(Dispatchers.Main) { result.error("READ_FAILED", "Failed to read image", null) }
                                    return@launch
                                }
                                val w = src.cols().toDouble()
                                val h = src.rows().toDouble()
                                val quad = listOf(
                                    Point(rawCorners[0] * w, rawCorners[1] * h),
                                    Point(rawCorners[2] * w, rawCorners[3] * h),
                                    Point(rawCorners[4] * w, rawCorners[5] * h),
                                    Point(rawCorners[6] * w, rawCorners[7] * h)
                                )
                                val warped = DocumentDetector.warp(src, quad, maxSide)
                                src.release()

                                val finalWarped = if (quarterTurns % 4 != 0) {
                                    val rotated = Mat()
                                    val turns = (quarterTurns % 4 + 4) % 4
                                    when (turns) {
                                        1 -> Core.rotate(warped, rotated, Core.ROTATE_90_COUNTERCLOCKWISE)
                                        2 -> Core.rotate(warped, rotated, Core.ROTATE_180)
                                        3 -> Core.rotate(warped, rotated, Core.ROTATE_90_CLOCKWISE)
                                    }
                                    warped.release()
                                    rotated
                                } else {
                                    warped
                                }

                                val outFile = File(outPath)
                                outFile.parentFile?.mkdirs()
                                val writeParams = MatOfInt(Imgcodecs.IMWRITE_JPEG_QUALITY, 95)
                                val success = Imgcodecs.imwrite(outPath, finalWarped, writeParams)
                                writeParams.release()
                                finalWarped.release()

                                val warpDuration = SystemClock.elapsedRealtime() - warpStart
                                android.util.Log.d("DocScan", "Warp time (transform + write): ${warpDuration}ms -> $outPath (maxSide=$maxSide, quarterTurns=$quarterTurns, reduced=$useReduced)")

                                withContext(Dispatchers.Main) {
                                    if (success) result.success(outPath)
                                    else result.error("WRITE_FAILED", "Failed to write warped image", null)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("WARP_ERROR", e.message, null)
                                }
                            } finally {
                                nativeOpSemaphore.release()
                            }
                        }
                    }
                    "applyFilter" -> {
                        val path = call.argument<String>("path")
                        val filter = call.argument<String>("filter") ?: "enhance"
                        val maxSide = call.argument<Int>("maxSide") ?: 0
                        val outPath = call.argument<String>("outPath")
                        if (path.isNullOrBlank() || outPath.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "path and outPath are required", null)
                            return@setMethodCallHandler
                        }
                        mainScope.launch(Dispatchers.Default) {
                            nativeOpSemaphore.acquire()
                            try {
                                val success = ImageFilters.runFile(path, outPath, filter, maxSide)
                                withContext(Dispatchers.Main) {
                                    if (success) result.success(outPath)
                                    else result.error("FILTER_FAILED", "Failed to apply filter $filter", null)
                                }
                            } finally {
                                nativeOpSemaphore.release()
                            }
                        }
                    }
                    "rotateLeft" -> {
                        val path = call.argument<String>("path")
                        val outPath = call.argument<String>("outPath")
                        if (path.isNullOrBlank() || outPath.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "path and outPath are required", null)
                            return@setMethodCallHandler
                        }
                        mainScope.launch(Dispatchers.Default) {
                            nativeOpSemaphore.acquire()
                            try {
                                val src = Imgcodecs.imread(path, Imgcodecs.IMREAD_COLOR)
                                if (src.empty()) {
                                    withContext(Dispatchers.Main) { result.error("READ_FAILED", "Failed to read image", null) }
                                    return@launch
                                }
                                val rotated = Mat()
                                Core.rotate(src, rotated, Core.ROTATE_90_COUNTERCLOCKWISE)
                                src.release()

                                val outFile = File(outPath)
                                outFile.parentFile?.mkdirs()
                                val writeParams = MatOfInt(Imgcodecs.IMWRITE_JPEG_QUALITY, 95)
                                val success = Imgcodecs.imwrite(outPath, rotated, writeParams)
                                writeParams.release()
                                rotated.release()

                                withContext(Dispatchers.Main) {
                                    if (success) result.success(outPath)
                                    else result.error("WRITE_FAILED", "Failed to write rotated image", null)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("ROTATE_ERROR", e.message, null)
                                }
                            } finally {
                                nativeOpSemaphore.release()
                            }
                        }
                    }
                    "compositeSignature" -> {
                        val pagePath = call.argument<String>("pagePath")
                        val sigBytes = call.argument<ByteArray>("signatureBytes")
                        val relX = call.argument<Double>("relX") ?: 0.05
                        val relY = call.argument<Double>("relY") ?: 0.70
                        val relW = call.argument<Double>("relW") ?: 0.40
                        val maxSide = call.argument<Int>("maxSide") ?: 2048
                        if (pagePath.isNullOrBlank() || sigBytes == null || sigBytes.isEmpty()) {
                            result.error("INVALID_ARGS", "pagePath and signatureBytes are required", null)
                            return@setMethodCallHandler
                        }
                        mainScope.launch(Dispatchers.Default) {
                            val startMs = SystemClock.elapsedRealtime()
                            try {
                                val rawPage = BitmapFactory.decodeFile(pagePath)
                                if (rawPage == null) {
                                    withContext(Dispatchers.Main) {
                                        result.error("DECODE_PAGE_FAILED", "Failed to decode page image", null)
                                    }
                                    return@launch
                                }
                                // Respect EXIF orientation if present
                                val exif = androidx.exifinterface.media.ExifInterface(pagePath)
                                val orientation = exif.getAttributeInt(
                                    androidx.exifinterface.media.ExifInterface.TAG_ORIENTATION,
                                    androidx.exifinterface.media.ExifInterface.ORIENTATION_NORMAL
                                )
                                val rotationDegrees = when (orientation) {
                                    androidx.exifinterface.media.ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                                    androidx.exifinterface.media.ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                                    androidx.exifinterface.media.ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                                    else -> 0f
                                }
                                var orientedPage = if (rotationDegrees != 0f) {
                                    val m = android.graphics.Matrix().apply { postRotate(rotationDegrees) }
                                    val rotated = android.graphics.Bitmap.createBitmap(
                                        rawPage, 0, 0, rawPage.width, rawPage.height, m, true
                                    )
                                    if (rotated !== rawPage) rawPage.recycle()
                                    rotated
                                } else {
                                    rawPage
                                }

                                // Cap longer side to maxSide (2048px) so PdfBuilderService hits the 0ms fast path
                                val longerSide = max(orientedPage.width, orientedPage.height)
                                if (maxSide > 0 && longerSide > maxSide) {
                                    val scale = maxSide.toFloat() / longerSide.toFloat()
                                    val newW = (orientedPage.width * scale).toInt().coerceAtLeast(1)
                                    val newH = (orientedPage.height * scale).toInt().coerceAtLeast(1)
                                    val scaled = android.graphics.Bitmap.createScaledBitmap(orientedPage, newW, newH, true)
                                    if (scaled !== orientedPage) orientedPage.recycle()
                                    orientedPage = scaled
                                }

                                val mutablePage = if (orientedPage.isMutable && orientedPage.config == android.graphics.Bitmap.Config.ARGB_8888) {
                                    orientedPage
                                } else {
                                    val copy = orientedPage.copy(android.graphics.Bitmap.Config.ARGB_8888, true)
                                    if (copy !== orientedPage) orientedPage.recycle()
                                    copy
                                }

                                val sigBitmap = BitmapFactory.decodeByteArray(sigBytes, 0, sigBytes.size)
                                if (sigBitmap == null) {
                                    mutablePage.recycle()
                                    withContext(Dispatchers.Main) {
                                        result.error("DECODE_SIG_FAILED", "Failed to decode signature PNG", null)
                                    }
                                    return@launch
                                }

                                val targetWidth = (mutablePage.width * relW).toInt().coerceIn(10, mutablePage.width)
                                val aspectRatio = sigBitmap.height.toFloat() / sigBitmap.width.toFloat().coerceAtLeast(1f)
                                val targetHeight = (targetWidth * aspectRatio).toInt().coerceIn(1, mutablePage.height)
                                val offsetX = (mutablePage.width * relX).toInt().coerceIn(0, (mutablePage.width - targetWidth).coerceAtLeast(0))
                                val offsetY = (mutablePage.height * relY).toInt().coerceIn(0, (mutablePage.height - targetHeight).coerceAtLeast(0))

                                val canvas = android.graphics.Canvas(mutablePage)
                                val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG or android.graphics.Paint.FILTER_BITMAP_FLAG)
                                val dstRect = android.graphics.RectF(
                                    offsetX.toFloat(),
                                    offsetY.toFloat(),
                                    (offsetX + targetWidth).toFloat(),
                                    (offsetY + targetHeight).toFloat()
                                )
                                canvas.drawBitmap(sigBitmap, null, dstRect, paint)
                                sigBitmap.recycle()

                                val baos = java.io.ByteArrayOutputStream(mutablePage.width * mutablePage.height / 4)
                                mutablePage.compress(android.graphics.Bitmap.CompressFormat.JPEG, 92, baos)
                                mutablePage.recycle()
                                val outBytes = baos.toByteArray()

                                val elapsed = SystemClock.elapsedRealtime() - startMs
                                android.util.Log.d("DocScan", "compositeSignature completed in ${elapsed}ms (${outBytes.size} bytes)")

                                withContext(Dispatchers.Main) {
                                    result.success(outBytes)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("COMPOSITE_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun replyScannerResult(block: (MethodChannel.Result) -> Unit) {
        val pending = pendingScannerResult ?: return
        pendingScannerResult = null
        try {
            block(pending)
        } catch (e: Exception) {
            android.util.Log.e("DocScan", "Failed to reply to scanner result", e)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_SCANNER) {
            replyScannerResult { pending ->
                if (resultCode == Activity.RESULT_OK && data != null) {
                    val batchList = data.getParcelableArrayListExtra<Bundle>(ScannerActivity.RESULT_BATCH_LIST)
                    if (batchList != null && batchList.isNotEmpty()) {
                        val results = batchList.map { b ->
                            mapOf(
                                "path" to (b.getString(ScannerActivity.RESULT_PATH) ?: ""),
                                "corners" to (b.getDoubleArray(ScannerActivity.RESULT_CORNERS)?.toList() ?: emptyList<Double>()),
                                "width" to b.getInt(ScannerActivity.RESULT_WIDTH, 0),
                                "height" to b.getInt(ScannerActivity.RESULT_HEIGHT, 0)
                            )
                        }
                        pending.success(mapOf("batch" to true, "items" to results))
                    } else {
                        val path = data.getStringExtra(ScannerActivity.RESULT_PATH)
                        val corners = data.getDoubleArrayExtra(ScannerActivity.RESULT_CORNERS)
                        val width = data.getIntExtra(ScannerActivity.RESULT_WIDTH, 0)
                        val height = data.getIntExtra(ScannerActivity.RESULT_HEIGHT, 0)
                        if (path != null && corners != null) {
                            pending.success(
                                mapOf(
                                    "batch" to false,
                                    "path" to path,
                                    "corners" to corners.toList(),
                                    "width" to width,
                                    "height" to height
                                )
                            )
                        } else {
                            pending.error("SCANNER_FAILED", "Incomplete scan result", null)
                        }
                    }
                } else {
                    pending.success(null)
                }
            }
        }
    }

    override fun onDestroy() {
        replyScannerResult { it.success(null) }
        mainScope.cancel()
        super.onDestroy()
    }
}
