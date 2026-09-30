package com.example.mobile_app.scanner

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.view.View
import android.widget.FrameLayout
import org.opencv.core.Point

/**
 * Custom FrameLayout that enforces a strict target aspect ratio (width / height).
 */
class AspectRatioFrameLayout(
    context: Context,
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
 * Live camera overlay view that draws a translucent polygon, glowing border,
 * and corner indicators over the detected document quadrilateral.
 */
open class QuadOverlayView(context: Context) : View(context) {

    private val density = resources.displayMetrics.density

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = Color.parseColor("#3800E676") // Translucent emerald green
    }

    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = Color.parseColor("#FF00E676") // Vibrant green border
        strokeWidth = 3.2f * density
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    private val cornerFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = Color.WHITE
    }

    private val cornerStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = Color.parseColor("#FF00C853")
        strokeWidth = 2.5f * density
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

        val x0 = (pts[0].x * w).toFloat()
        val y0 = (pts[0].y * h).toFloat()
        val x1 = (pts[1].x * w).toFloat()
        val y1 = (pts[1].y * h).toFloat()
        val x2 = (pts[2].x * w).toFloat()
        val y2 = (pts[2].y * h).toFloat()
        val x3 = (pts[3].x * w).toFloat()
        val y3 = (pts[3].y * h).toFloat()

        path.reset()
        path.moveTo(x0, y0)
        path.lineTo(x1, y1)
        path.lineTo(x2, y2)
        path.lineTo(x3, y3)
        path.close()

        canvas.drawPath(path, fillPaint)
        canvas.drawPath(path, strokePaint)

        // Draw corner dots for clear visual lock feedback
        val radius = 6.5f * density
        val corners = arrayOf(
            floatArrayOf(x0, y0),
            floatArrayOf(x1, y1),
            floatArrayOf(x2, y2),
            floatArrayOf(x3, y3)
        )
        for (c in corners) {
            canvas.drawCircle(c[0], c[1], radius, cornerFillPaint)
            canvas.drawCircle(c[0], c[1], radius, cornerStrokePaint)
        }
    }
}

/**
 * Alias kept for backward compatibility.
 */
class PolygonOverlayView(context: Context) : QuadOverlayView(context)
