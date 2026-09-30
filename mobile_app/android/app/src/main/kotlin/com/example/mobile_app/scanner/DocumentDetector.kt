package com.example.mobile_app.scanner

import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
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
import kotlin.math.roundToInt

object DocumentDetector {

    private val EPSILONS = doubleArrayOf(0.018, 0.025, 0.035)

    /**
     * Finds a precise 4-corner document quad in a single-channel grayscale Mat.
     *
     * Optional [priorNormalizedQuad] (in [0..1] upright coordinates) provides spatial hysteresis
     * so that once a paper is locked, the detector strongly prefers keeping that paper rather
     * than jumping to another object in the scene.
     *
     * Orders points: [TL, TR, BR, BL] in original source coordinates.
     * Returns null if no high-confidence document quad is detected.
     */
    fun findQuad(gray: Mat, priorNormalizedQuad: List<Point>? = null): List<Point>? {
        if (gray.empty() || gray.cols() <= 0 || gray.rows() <= 0) return null

        val originalWidth = gray.cols().toDouble()
        val originalHeight = gray.rows().toDouble()
        val longerSide = max(originalWidth, originalHeight)
        val targetLongSide = 420.0
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

        // A real document being scanned occupies at least 10% of the viewport and at most 95%
        val minArea = downscaledArea * 0.10
        val maxAreaAllowed = downscaledArea * 0.95

        // Convert priorNormalizedQuad to downscaled pixel coordinates if available
        val priorDownscaled = if (priorNormalizedQuad != null && priorNormalizedQuad.size == 4) {
            priorNormalizedQuad.map { Point(it.x * w, it.y * h) }
        } else {
            null
        }

        val blurred = Mat()
        val morphClosedGray = Mat()
        val cannyClosed = Mat()
        val cannyStandard = Mat()
        val otsuBinary = Mat()
        val combinedEdges = Mat()
        val edgeSupportMask = Mat()

        val kernelCloseGray = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(9.0, 9.0))
        val kernel3 = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(3.0, 3.0))
        val kernel5 = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(5.0, 5.0))

        var bestQuad: List<Point>? = null
        var bestScore = 0.0

        try {
            // 1. Smooth noise while keeping outer boundaries
            Imgproc.GaussianBlur(downscaled, blurred, Size(5.0, 5.0), 0.0)

            // 2. Morphological closing (9x9) on grayscale erases dark text/lines INSIDE the paper
            // while preserving the bright rectangular body of the document against the background.
            Imgproc.morphologyEx(blurred, morphClosedGray, Imgproc.MORPH_CLOSE, kernelCloseGray)
            Imgproc.GaussianBlur(morphClosedGray, morphClosedGray, Size(5.0, 5.0), 0.0)

            // Compute Otsu threshold on the text-suppressed grayscale image
            val otsuVal = Imgproc.threshold(
                morphClosedGray,
                otsuBinary,
                0.0,
                255.0,
                Imgproc.THRESH_BINARY or Imgproc.THRESH_OTSU
            ).coerceIn(55.0, 215.0)

            // Clean up Otsu binary mask so internal holes are filled
            Imgproc.morphologyEx(otsuBinary, otsuBinary, Imgproc.MORPH_CLOSE, kernel5)

            // Canny on text-suppressed image (primary clean document edge map)
            Imgproc.Canny(morphClosedGray, cannyClosed, 0.45 * otsuVal, otsuVal)

            // Standard Canny on blurred image (for sharper contrast edges)
            Imgproc.Canny(blurred, cannyStandard, 55.0, 145.0)

            // Build a unified 3px dilated edge support mask to verify that candidate quad sides
            // actually lie on true physical edges in the image.
            Core.bitwise_or(cannyClosed, cannyStandard, combinedEdges)
            Imgproc.dilate(combinedEdges, edgeSupportMask, kernel3)

            // Prepare contour passes:
            // Pass A: Canny on text-suppressed image (dilated slightly to bridge 1-2px corner gaps)
            val passA = Mat()
            Imgproc.dilate(cannyClosed, passA, kernel3)

            // Pass B: Otsu binary document body mask
            val passB = otsuBinary

            // Pass C: Combined Canny + 5x5 close
            val passC = Mat()
            Imgproc.morphologyEx(combinedEdges, passC, Imgproc.MORPH_CLOSE, kernel5)

            val passes = listOf(passA, passB, passC)

            try {
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
                    val candidates = contours.take(6)

                    for (contour in candidates) {
                        val contourArea = Imgproc.contourArea(contour)
                        if (contourArea < minArea || contourArea > maxAreaAllowed) continue

                        val candidatePts = extractStrictQuad(contour, contourArea, minArea, maxAreaAllowed)
                        if (candidatePts != null) {
                            val score = evaluateDocumentConfidence(
                                ordered = candidatePts,
                                contourArea = contourArea,
                                gray = morphClosedGray,
                                edgeMask = edgeSupportMask,
                                priorQuad = priorDownscaled,
                                frameW = w,
                                frameH = h
                            )
                            if (score > bestScore) {
                                bestScore = score
                                bestQuad = candidatePts
                            }
                        }
                    }

                    for (c in contours) {
                        c.release()
                    }
                }
            } finally {
                passA.release()
                passC.release()
            }
        } finally {
            downscaled.release()
            blurred.release()
            morphClosedGray.release()
            cannyClosed.release()
            cannyStandard.release()
            otsuBinary.release()
            combinedEdges.release()
            edgeSupportMask.release()
            kernelCloseGray.release()
            kernel3.release()
            kernel5.release()
        }

        // Minimum confidence threshold required to accept a quad as a real document
        val minConfidenceScore = downscaledArea * 0.085
        val finalBest = if (bestScore >= minConfidenceScore) bestQuad else null
        if (finalBest == null) return null

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
     * Extracts a 4-corner polygon ONLY if the contour genuinely approximates to 4 straight sides
     * whose polygon area matches the raw contour area within 12% (rejecting random blobs/wires).
     */
    private fun extractStrictQuad(
        contour: MatOfPoint,
        contourArea: Double,
        minArea: Double,
        maxAreaAllowed: Double
    ): List<Point>? {
        val c2f = MatOfPoint2f(*contour.toArray())
        val peri = Imgproc.arcLength(c2f, true)

        try {
            for (eps in EPSILONS) {
                val approx = MatOfPoint2f()
                Imgproc.approxPolyDP(c2f, approx, eps * peri, true)
                val total = approx.total()
                if (total == 4L) {
                    val pts = approx.toArray().toList()
                    approx.release()
                    val ordered = orderPoints(pts)

                    val quadMat = MatOfPoint(*ordered.toTypedArray())
                    val isConvex = Imgproc.isContourConvex(quadMat)
                    val quadArea = Imgproc.contourArea(quadMat)
                    quadMat.release()

                    if (!isConvex || quadArea < minArea || quadArea > maxAreaAllowed) {
                        continue
                    }

                    // The raw contour must tightly match the 4-point polygon area (no random blobs)
                    val areaRatio = contourArea / quadArea
                    if (areaRatio < 0.88 || areaRatio > 1.12) {
                        continue
                    }

                    if (isValidPaperGeometry(ordered)) {
                        return ordered
                    }
                } else {
                    approx.release()
                }
            }
        } finally {
            c2f.release()
        }
        return null
    }

    /**
     * Checks that the 4 ordered points [TL, TR, BR, BL] have realistic perspective-paper proportions:
     * - Interior angles in [62°, 118°]
     * - Opposite side length ratios <= 1.55 (no extreme trapezoids)
     * - Aspect ratio in [0.38, 2.6]
     */
    private fun isValidPaperGeometry(ordered: List<Point>): Boolean {
        if (ordered.size != 4) return false

        val topW = hypot(ordered[1].x - ordered[0].x, ordered[1].y - ordered[0].y)
        val rightH = hypot(ordered[2].x - ordered[1].x, ordered[2].y - ordered[1].y)
        val bottomW = hypot(ordered[2].x - ordered[3].x, ordered[2].y - ordered[3].y)
        val leftH = hypot(ordered[3].x - ordered[0].x, ordered[3].y - ordered[0].y)

        val minSide = min(min(topW, bottomW), min(leftH, rightH))
        if (minSide < 32.0) return false

        // Opposite sides on a rectangular sheet under normal camera perspective cannot differ > 1.55x
        val widthRatio = max(topW, bottomW) / min(topW, bottomW).coerceAtLeast(1.0)
        val heightRatio = max(leftH, rightH) / min(leftH, rightH).coerceAtLeast(1.0)
        if (widthRatio > 1.55 || heightRatio > 1.55) return false

        val avgW = (topW + bottomW) * 0.5
        val avgH = (leftH + rightH) * 0.5
        val aspect = avgW / avgH.coerceAtLeast(1.0)
        if (aspect < 0.38 || aspect > 2.60) return false

        // Interior angles must be close to 90° (allow 62°..118° for camera tilt)
        for (i in 0..3) {
            val prev = ordered[(i + 3) % 4]
            val curr = ordered[i]
            val next = ordered[(i + 1) % 4]
            val angle = angleBetweenDegrees(prev, curr, next)
            if (angle < 62.0 || angle > 118.0) return false
        }

        return true
    }

    /**
     * Evaluates physical evidence that [ordered] is an actual paper sheet:
     * 1. All 4 boundary segments must lie on strong Canny edges (`edgeSupportMask`).
     * 2. The interior along the 4 edges must be brighter/cleaner than the exterior background.
     * 3. Rectangularity and viewport-border penalty.
     * 4. Spatial lock bonus if [ordered] matches [priorQuad].
     */
    private fun evaluateDocumentConfidence(
        ordered: List<Point>,
        contourArea: Double,
        gray: Mat,
        edgeMask: Mat,
        priorQuad: List<Point>?,
        frameW: Double,
        frameH: Double
    ): Double {
        // Reject quads that hug >= 3 edges of the camera sensor viewport
        val marginX = frameW * 0.02
        val marginY = frameH * 0.02
        var borderCorners = 0
        for (p in ordered) {
            if (p.x <= marginX || p.x >= frameW - marginX || p.y <= marginY || p.y >= frameH - marginY) {
                borderCorners++
            }
        }
        if (borderCorners >= 3) return 0.0

        // 1. Verify Canny edge support along each of the 4 sides
        val edgeSupport = measureEdgeSupport(ordered, edgeMask)
        if (edgeSupport < 0.76) return 0.0

        // 2. Verify that the inside of the quad is paper-like (brighter than outside border)
        val contrastFactor = measureInteriorVsExteriorBrightness(ordered, gray)
        if (contrastFactor <= 0.0) return 0.0

        // 3. Rectangularity check
        val matPt2f = MatOfPoint2f(*ordered.toTypedArray())
        val minRect = Imgproc.minAreaRect(matPt2f)
        matPt2f.release()
        val rectArea = (minRect.size.width * minRect.size.height).coerceAtLeast(1.0)
        val rectangularity = (contourArea / rectArea).coerceIn(0.0, 1.0)
        if (rectangularity < 0.72) return 0.0

        // 4. Spatial hysteresis bonus if this quad matches the previously locked paper
        var lockBonus = 1.0
        if (priorQuad != null && priorQuad.size == 4) {
            val diag = hypot(frameW, frameH)
            var maxCornerDist = 0.0
            for (i in 0..3) {
                val d = hypot(ordered[i].x - priorQuad[i].x, ordered[i].y - priorQuad[i].y) / diag
                if (d > maxCornerDist) maxCornerDist = d
            }
            if (maxCornerDist < 0.08) {
                // Strong bonus to keep the current paper locked rather than switching to another object
                lockBonus = 1.45
            }
        }

        return contourArea * rectangularity * edgeSupport * contrastFactor * lockBonus
    }

    /**
     * Samples points along each of the 4 sides of [ordered] in [edgeMask].
     * Returns 0.0 if any single side has < 65% edge support; otherwise returns the average support.
     */
    private fun measureEdgeSupport(ordered: List<Point>, edgeMask: Mat): Double {
        val cols = edgeMask.cols()
        val rows = edgeMask.rows()
        val samplesPerSide = 24
        var totalSupport = 0.0

        for (side in 0..3) {
            val p1 = ordered[side]
            val p2 = ordered[(side + 1) % 4]
            var hits = 0

            // Sample from 8% to 92% along the side (avoiding corner rounding artifacts)
            for (s in 1..samplesPerSide) {
                val t = 0.08 + 0.84 * (s.toDouble() / (samplesPerSide + 1).toDouble())
                val x = (p1.x + t * (p2.x - p1.x)).roundToInt().coerceIn(0, cols - 1)
                val y = (p1.y + t * (p2.y - p1.y)).roundToInt().coerceIn(0, rows - 1)

                val v = edgeMask.get(y, x)
                if (v != null && v[0] > 0.0) {
                    hits++
                }
            }

            val sideRatio = hits.toDouble() / samplesPerSide.toDouble()
            // Every single side of the paper must have real edge pixels along >= 65% of its length
            if (sideRatio < 0.65) return 0.0
            totalSupport += sideRatio
        }

        return totalSupport / 4.0
    }

    /**
     * Compares pixel brightness slightly inside the quad vs slightly outside the quad,
     * and checks that the interior of the document is reasonably bright (> 95 gray level).
     */
    private fun measureInteriorVsExteriorBrightness(ordered: List<Point>, gray: Mat): Double {
        val cols = gray.cols()
        val rows = gray.rows()
        val cx = (ordered[0].x + ordered[1].x + ordered[2].x + ordered[3].x) * 0.25
        val cy = (ordered[0].y + ordered[1].y + ordered[2].y + ordered[3].y) * 0.25

        var insideSum = 0.0
        var outsideSum = 0.0
        var count = 0

        for (side in 0..3) {
            val p1 = ordered[side]
            val p2 = ordered[(side + 1) % 4]
            for (s in 1..10) {
                val t = s.toDouble() / 11.0
                val bx = p1.x + t * (p2.x - p1.x)
                val by = p1.y + t * (p2.y - p1.y)

                // Vector from centroid to border point
                val vx = bx - cx
                val vy = by - cy

                // 8% inward toward centroid (inside the paper margin)
                val inX = (bx - 0.08 * vx).roundToInt().coerceIn(0, cols - 1)
                val inY = (by - 0.08 * vy).roundToInt().coerceIn(0, rows - 1)

                // 8% outward away from centroid (background just outside the paper)
                val outX = (bx + 0.08 * vx).roundToInt().coerceIn(0, cols - 1)
                val outY = (by + 0.08 * vy).roundToInt().coerceIn(0, rows - 1)

                val inVal = gray.get(inY, inX)?.get(0) ?: 0.0
                val outVal = gray.get(outY, outX)?.get(0) ?: 0.0

                insideSum += inVal
                outsideSum += outVal
                count++
            }
        }

        if (count == 0) return 0.0
        val meanIn = insideSum / count
        val meanOut = outsideSum / count

        // A real sheet of paper has a relatively light interior (at least > 90 luminance)
        if (meanIn < 90.0) return 0.0

        val diff = meanIn - meanOut
        // Paper should either be noticeably brighter than the background (diff >= 8)
        // or be a very bright sheet (meanIn >= 155) with clear edge contrast (abs(diff) >= 6)
        return when {
            diff >= 18.0 -> 1.25
            diff >= 8.0 -> 1.05
            meanIn >= 155.0 && abs(diff) >= 6.0 -> 0.95
            else -> 0.0
        }
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
