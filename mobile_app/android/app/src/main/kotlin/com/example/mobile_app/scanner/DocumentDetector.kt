package com.example.mobile_app.scanner

import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfInt
import org.opencv.core.MatOfPoint
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Point
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

object DocumentDetector {

    private val EPSILONS = doubleArrayOf(0.015, 0.02, 0.03, 0.04, 0.05)

    /**
     * Finds the 4-corner document quad in a single-channel grayscale Mat.
     * Orders points: [TL, TR, BR, BL] in original source coordinates.
     * Returns null if no valid document quad is detected.
     */
    fun findQuad(gray: Mat): List<Point>? {
        if (gray.empty() || gray.cols() <= 0 || gray.rows() <= 0) return null

        val originalWidth = gray.cols().toDouble()
        val originalHeight = gray.rows().toDouble()
        val longerSide = max(originalWidth, originalHeight)
        val targetLongSide = 400.0
        val scale = if (longerSide > targetLongSide) targetLongSide / longerSide else 1.0

        val downscaled = Mat()
        if (scale < 1.0) {
            Imgproc.resize(
                gray,
                downscaled,
                Size(originalWidth * scale, originalHeight * scale),
                0.0,
                0.0,
                Imgproc.INTER_AREA
            )
        } else {
            gray.copyTo(downscaled)
        }

        val w = downscaled.cols().toDouble()
        val h = downscaled.rows().toDouble()
        val downscaledArea = w * h
        // Allow papers from 4% of the frame (distant/small sheets) up to 98% (close-up)
        val minArea = downscaledArea * 0.04
        val maxAreaAllowed = downscaledArea * 0.98

        val blurred = Mat()
        val claheMat = Mat()
        val claheBlurred = Mat()
        val otsuBinary = Mat()
        val passCannyClahe = Mat()
        val passCannyOtsu = Mat()
        val passOtsuClosed = Mat()
        val passAdaptive = Mat()

        val kernel3 = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(3.0, 3.0))
        val kernel5 = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(5.0, 5.0))
        val kernel7 = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(7.0, 7.0))

        var bestQuad: List<Point>? = null
        var bestScore = 0.0

        try {
            Imgproc.GaussianBlur(downscaled, blurred, Size(5.0, 5.0), 0.0)

            // Enhance local contrast via CLAHE so white paper on a light desk pops out
            val clahe = Imgproc.createCLAHE(2.5, Size(8.0, 8.0))
            clahe.apply(blurred, claheMat)
            Imgproc.GaussianBlur(claheMat, claheBlurred, Size(3.0, 3.0), 0.0)

            // Compute Otsu threshold value on blurred image
            val otsuVal = Imgproc.threshold(
                blurred,
                otsuBinary,
                0.0,
                255.0,
                Imgproc.THRESH_BINARY or Imgproc.THRESH_OTSU
            ).coerceIn(40.0, 210.0)

            // Pass 1: Sensitive Canny on CLAHE-enhanced image + MORPH_CLOSE 5x5 to bridge gaps
            Imgproc.Canny(claheBlurred, passCannyClahe, 25.0, 75.0)
            Imgproc.dilate(passCannyClahe, passCannyClahe, kernel3)
            Imgproc.morphologyEx(passCannyClahe, passCannyClahe, Imgproc.MORPH_CLOSE, kernel5)

            // Pass 2: Dynamic Otsu-scaled Canny on blurred image + MORPH_CLOSE 5x5
            Imgproc.Canny(blurred, passCannyOtsu, 0.4 * otsuVal, otsuVal)
            Imgproc.dilate(passCannyOtsu, passCannyOtsu, kernel3)
            Imgproc.morphologyEx(passCannyOtsu, passCannyOtsu, Imgproc.MORPH_CLOSE, kernel5)

            // Pass 3: Solid Otsu binary region + MORPH_CLOSE 7x7
            Imgproc.morphologyEx(otsuBinary, passOtsuClosed, Imgproc.MORPH_CLOSE, kernel7)

            // Pass 4: Adaptive threshold for uneven shadow across page
            Imgproc.adaptiveThreshold(
                claheBlurred,
                passAdaptive,
                255.0,
                Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
                Imgproc.THRESH_BINARY_INV,
                21,
                5.0
            )
            Imgproc.morphologyEx(passAdaptive, passAdaptive, Imgproc.MORPH_CLOSE, kernel5)

            val passes = listOf(passCannyClahe, passCannyOtsu, passOtsuClosed, passAdaptive)

            for (passMat in passes) {
                val contours = ArrayList<MatOfPoint>()
                val hierarchy = Mat()
                Imgproc.findContours(
                    passMat,
                    contours,
                    hierarchy,
                    Imgproc.RETR_LIST,
                    Imgproc.CHAIN_APPROX_SIMPLE
                )
                hierarchy.release()

                contours.sortByDescending { Imgproc.contourArea(it) }
                val candidates = contours.take(8)

                for (contour in candidates) {
                    val rawArea = Imgproc.contourArea(contour)
                    if (rawArea < minArea * 0.75) continue

                    val candidatePts = extractQuadFromContour(contour, minArea, maxAreaAllowed, w, h)
                    if (candidatePts != null) {
                        val ordered = orderPoints(candidatePts)
                        val score = scoreCandidateQuad(ordered, w, h, minArea, maxAreaAllowed)
                        if (score > bestScore) {
                            bestScore = score
                            bestQuad = ordered
                        }
                    }
                }

                for (c in contours) {
                    c.release()
                }

                // Early exit if we already locked onto a high-confidence document quad (> 25% of frame)
                if (bestScore > downscaledArea * 0.25) {
                    break
                }
            }
        } finally {
            downscaled.release()
            blurred.release()
            claheMat.release()
            claheBlurred.release()
            otsuBinary.release()
            passCannyClahe.release()
            passCannyOtsu.release()
            passOtsuClosed.release()
            passAdaptive.release()
            kernel3.release()
            kernel5.release()
            kernel7.release()
        }

        val finalBest = bestQuad ?: return null

        // Scale back to original coordinates
        val invScale = 1.0 / scale
        val scaledQuad = finalBest.map {
            Point(
                (it.x * invScale).coerceIn(0.0, originalWidth),
                (it.y * invScale).coerceIn(0.0, originalHeight)
            )
        }

        return orderPoints(scaledQuad)
    }

    /**
     * Attempts to extract a valid 4-corner quadrilateral from [contour] using:
     * 1. Convex hull + multi-epsilon approxPolyDP (handles fingers/shadows/dents on edges)
     * 2. Raw contour + multi-epsilon approxPolyDP
     * 3. High-rectangularity 4-extreme-corner fallback when 1 corner is slightly rounded/dog-eared
     */
    private fun extractQuadFromContour(
        contour: MatOfPoint,
        minArea: Double,
        maxAreaAllowed: Double,
        frameW: Double,
        frameH: Double
    ): List<Point>? {
        val hullIndices = MatOfInt()
        var hullContour: MatOfPoint? = null
        try {
            Imgproc.convexHull(contour, hullIndices)
            val contourPts = contour.toArray()
            val indices = hullIndices.toArray()
            if (indices.size >= 4) {
                val hullPts = Array(indices.size) { idx -> contourPts[indices[idx]] }
                hullContour = MatOfPoint(*hullPts)
            }

            // Try hull first (bridges edge gaps & finger occlusions), then raw contour
            val shapesToTry = listOfNotNull(hullContour, contour)
            for (shape in shapesToTry) {
                val shapeArea = Imgproc.contourArea(shape)
                if (shapeArea < minArea || shapeArea > maxAreaAllowed) continue

                val c2f = MatOfPoint2f(*shape.toArray())
                val peri = Imgproc.arcLength(c2f, true)

                for (eps in EPSILONS) {
                    val approx = MatOfPoint2f()
                    Imgproc.approxPolyDP(c2f, approx, eps * peri, true)
                    val total = approx.total()
                    if (total == 4L) {
                        val pts = approx.toArray().toList()
                        approx.release()
                        val ordered = orderPoints(pts)
                        if (isValidQuadGeometry(ordered, minArea, maxAreaAllowed)) {
                            c2f.release()
                            return ordered
                        }
                    } else {
                        approx.release()
                    }
                }

                // Fallback: if convex hull has 5..7 vertices and high rectangularity (e.g. rounded corner),
                // extract the 4 extreme corners using orderPoints on the hull vertices
                val rect = Imgproc.minAreaRect(c2f)
                val rectArea = rect.size.width * rect.size.height
                c2f.release()

                if (rectArea > minArea && (shapeArea / rectArea) >= 0.78) {
                    val extremeQuad = selectFourExtremeCorners(shape.toArray().toList())
                    if (extremeQuad != null && isValidQuadGeometry(extremeQuad, minArea, maxAreaAllowed)) {
                        return extremeQuad
                    }
                }
            }
        } finally {
            hullIndices.release()
            hullContour?.release()
        }
        return null
    }

    /**
     * Picks the 4 extreme corners [TL, TR, BR, BL] from a polygon with >= 4 vertices.
     */
    private fun selectFourExtremeCorners(pts: List<Point>): List<Point>? {
        if (pts.size < 4) return null
        val tl = pts.minByOrNull { it.x + it.y } ?: return null
        val br = pts.maxByOrNull { it.x + it.y } ?: return null
        val tr = pts.minByOrNull { it.y - it.x } ?: return null
        val bl = pts.maxByOrNull { it.y - it.x } ?: return null

        val distinct = setOf(tl, tr, br, bl)
        if (distinct.size < 4) return null
        return listOf(tl, tr, br, bl)
    }

    /**
     * Validates convexity, area, edge lengths, and interior angles (40°..140°) of an ordered [TL, TR, BR, BL] quad.
     */
    private fun isValidQuadGeometry(
        ordered: List<Point>,
        minArea: Double,
        maxAreaAllowed: Double
    ): Boolean {
        if (ordered.size != 4) return false

        val matPt = MatOfPoint(*ordered.toTypedArray())
        val isConvex = Imgproc.isContourConvex(matPt)
        val area = Imgproc.contourArea(matPt)
        matPt.release()

        if (!isConvex || area < minArea || area > maxAreaAllowed) return false

        // Check minimum side length to reject thin slivers
        val d0 = hypot(ordered[1].x - ordered[0].x, ordered[1].y - ordered[0].y)
        val d1 = hypot(ordered[2].x - ordered[1].x, ordered[2].y - ordered[1].y)
        val d2 = hypot(ordered[3].x - ordered[2].x, ordered[3].y - ordered[2].y)
        val d3 = hypot(ordered[0].x - ordered[3].x, ordered[0].y - ordered[3].y)
        val minSide = min(min(d0, d1), min(d2, d3))
        val maxSide = max(max(d0, d1), max(d2, d3))
        if (minSide < 20.0 || (maxSide / minSide) > 6.5) return false

        // Check all 4 interior angles are within [40°, 140°]
        for (i in 0..3) {
            val prev = ordered[(i + 3) % 4]
            val curr = ordered[i]
            val next = ordered[(i + 1) % 4]
            val angle = angleBetweenDegrees(prev, curr, next)
            if (angle < 40.0 || angle > 140.0) return false
        }

        return true
    }

    private fun angleBetweenDegrees(a: Point, b: Point, c: Point): Double {
        val vx1 = a.x - b.x
        val vy1 = a.y - b.y
        val vx2 = c.x - b.x
        val vy2 = c.y - b.y
        val len1 = hypot(vx1, vy1)
        val len2 = hypot(vx2, vy2)
        if (len1 < 1e-5 || len2 < 1e-5) return 0.0
        val cosTheta = ((vx1 * vx2 + vy1 * vy2) / (len1 * len2)).coerceIn(-1.0, 1.0)
        return Math.toDegrees(acos(cosTheta))
    }

    /**
     * Scores a valid ordered quad so true rectangular documents inside the camera frame
     * beat random background shapes or the full camera viewport border.
     */
    private fun scoreCandidateQuad(
        ordered: List<Point>,
        frameW: Double,
        frameH: Double,
        minArea: Double,
        maxAreaAllowed: Double
    ): Double {
        if (!isValidQuadGeometry(ordered, minArea, maxAreaAllowed)) return 0.0

        val matPt = MatOfPoint(*ordered.toTypedArray())
        val matPt2f = MatOfPoint2f(*ordered.toTypedArray())
        val area = Imgproc.contourArea(matPt)
        val minRect = Imgproc.minAreaRect(matPt2f)
        matPt.release()
        matPt2f.release()

        val rectArea = (minRect.size.width * minRect.size.height).coerceAtLeast(1.0)
        val rectangularity = (area / rectArea).coerceIn(0.0, 1.0)
        if (rectangularity < 0.62) return 0.0

        // Penalize contours that hug all 4 edges of the camera viewport
        val marginX = frameW * 0.015
        val marginY = frameH * 0.015
        var borderCorners = 0
        for (p in ordered) {
            if (p.x <= marginX || p.x >= frameW - marginX || p.y <= marginY || p.y >= frameH - marginY) {
                borderCorners++
            }
        }
        val borderPenalty = if (borderCorners >= 3) 0.35 else 1.0

        return area * rectangularity * borderPenalty
    }

    /**
     * Orders 4 points to [TL, TR, BR, BL] using the sum and (y - x) coordinate projection method.
     */
    fun orderPoints(pts: List<Point>): List<Point> {
        require(pts.size == 4) { "orderPoints requires exactly 4 points" }

        // TL: min(x + y), BR: max(x + y)
        val tl = pts.minByOrNull { it.x + it.y } ?: pts[0]
        val br = pts.maxByOrNull { it.x + it.y } ?: pts[2]

        // TR: min(y - x), BL: max(y - x)
        val remaining = pts.filter { it !== tl && it !== br }
        val tr: Point
        val bl: Point
        if (remaining.size == 2) {
            tr = remaining.minByOrNull { it.y - it.x } ?: remaining[0]
            bl = remaining.maxByOrNull { it.y - it.x } ?: remaining[1]
        } else {
            // Fallback in degenerate coordinate cases
            tr = pts.minByOrNull { it.y - it.x } ?: pts[1]
            bl = pts.maxByOrNull { it.y - it.x } ?: pts[3]
        }

        return listOf(tl, tr, br, bl)
    }

    /**
     * Warps the quadrilateral region in [src] into a rectified rectangular Mat.
     * Quad points must be [TL, TR, BR, BL].
     * Insets the quad by 0.5% toward its centroid to eliminate residual dark border slivers.
     */
    fun warp(src: Mat, quad: List<Point>, maxSide: Int = 0): Mat {
        require(quad.size == 4) { "warp requires 4 points (TL, TR, BR, BL)" }

        val tl = quad[0]
        val tr = quad[1]
        val br = quad[2]
        val bl = quad[3]

        val widthA = hypot(br.x - bl.x, br.y - bl.y)
        val widthB = hypot(tr.x - tl.x, tr.y - tl.y)
        var maxWidth = max(widthA, widthB).toInt().coerceAtLeast(100)

        val heightA = hypot(tr.x - br.x, tr.y - br.y)
        val heightB = hypot(tl.x - bl.x, tl.y - bl.y)
        var maxHeight = max(heightA, heightB).toInt().coerceAtLeast(100)

        if (maxSide > 0) {
            val longer = max(maxWidth, maxHeight)
            if (longer > maxSide) {
                val scale = maxSide.toDouble() / longer.toDouble()
                maxWidth = (maxWidth * scale).toInt().coerceAtLeast(50)
                maxHeight = (maxHeight * scale).toInt().coerceAtLeast(50)
            }
        }

        // Centroid calculation
        val cx = (tl.x + tr.x + br.x + bl.x) / 4.0
        val cy = (tl.y + tr.y + br.y + bl.y) / 4.0

        // Inset ~0.5% toward centroid to remove dark edge slivers
        val insetFactor = 0.005
        fun shrink(p: Point): Point {
            return Point(
                p.x + insetFactor * (cx - p.x),
                p.y + insetFactor * (cy - p.y)
            )
        }

        val shTl = shrink(tl)
        val shTr = shrink(tr)
        val shBr = shrink(br)
        val shBl = shrink(bl)

        val srcPoints = MatOfPoint2f(shTl, shTr, shBr, shBl)
        val dstPoints = MatOfPoint2f(
            Point(0.0, 0.0),
            Point((maxWidth - 1).toDouble(), 0.0),
            Point((maxWidth - 1).toDouble(), (maxHeight - 1).toDouble()),
            Point(0.0, (maxHeight - 1).toDouble())
        )

        val transformMatrix = Imgproc.getPerspectiveTransform(srcPoints, dstPoints)
        val destination = Mat()
        Imgproc.warpPerspective(
            src,
            destination,
            transformMatrix,
            Size(maxWidth.toDouble(), maxHeight.toDouble()),
            Imgproc.INTER_LINEAR,
            Core.BORDER_REPLICATE
        )

        srcPoints.release()
        dstPoints.release()
        transformMatrix.release()

        return destination
    }
}
