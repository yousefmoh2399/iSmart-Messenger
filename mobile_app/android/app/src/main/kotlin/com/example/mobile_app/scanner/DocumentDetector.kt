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
import kotlin.math.roundToInt
import kotlin.math.sqrt

object DocumentDetector {

    private val EPSILONS = doubleArrayOf(0.015, 0.022, 0.032, 0.045)

    /**
     * Finds a 4-corner document quad in a single-channel grayscale Mat across any normal
     * shooting distance (from 5% of the camera frame up to 98% close-up).
     *
     * Uses scale-independent quality scoring (4-side physical edge support + interior paper
     * contrast + perspective rectangle geometry) so distant papers and close-up papers are
     * detected equally fast while random non-paper objects are rejected.
     */
    fun findQuad(gray: Mat, priorNormalizedQuad: List<Point>? = null): List<Point>? {
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

        // Distance-independent area range:
        // 4.5% (distant sheet / receipt / ID card) up to 98% (very close sheet)
        val minArea = downscaledArea * 0.045
        val maxAreaAllowed = downscaledArea * 0.98

        val priorDownscaled = if (priorNormalizedQuad != null && priorNormalizedQuad.size == 4) {
            priorNormalizedQuad.map { Point(it.x * w, it.y * h) }
        } else {
            null
        }

        val blurred = Mat()
        val morphClosedGray = Mat()
        val claheGray = Mat()
        val cannyClosed = Mat()
        val cannySensitive = Mat()
        val otsuBinary = Mat()
        val combinedEdges = Mat()
        val edgeSupportMask = Mat()

        val kernelClose7 = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(7.0, 7.0))
        val kernel5 = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(5.0, 5.0))
        val kernel3 = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(3.0, 3.0))

        var bestQuad: List<Point>? = null
        var bestScore = 0.0

        try {
            Imgproc.GaussianBlur(downscaled, blurred, Size(5.0, 5.0), 0.0)

            // Suppress internal dark text/lines inside the paper while keeping outer boundaries
            Imgproc.morphologyEx(blurred, morphClosedGray, Imgproc.MORPH_CLOSE, kernelClose7)
            Imgproc.GaussianBlur(morphClosedGray, morphClosedGray, Size(3.0, 3.0), 0.0)

            // Enhance local contrast so distant or low-contrast papers stand out clearly
            val clahe = Imgproc.createCLAHE(2.0, Size(8.0, 8.0))
            clahe.apply(morphClosedGray, claheGray)

            val otsuVal = Imgproc.threshold(
                morphClosedGray,
                otsuBinary,
                0.0,
                255.0,
                Imgproc.THRESH_BINARY or Imgproc.THRESH_OTSU
            ).coerceIn(50.0, 210.0)

            Imgproc.morphologyEx(otsuBinary, otsuBinary, Imgproc.MORPH_CLOSE, kernel5)

            // Primary Canny on text-suppressed grayscale
            Imgproc.Canny(morphClosedGray, cannyClosed, 0.40 * otsuVal, otsuVal)

            // Sensitive Canny on CLAHE image for distant/soft-lit papers
            Imgproc.Canny(claheGray, cannySensitive, 35.0, 105.0)

            // Build 5x5 dilated edge support mask for verifying candidate quad sides
            Core.bitwise_or(cannyClosed, cannySensitive, combinedEdges)
            Imgproc.dilate(combinedEdges, edgeSupportMask, kernel5)

            // Pass 1: Closed Canny edges (works at any distance: far, medium, close)
            val passCannyClosed = Mat()
            Imgproc.morphologyEx(cannyClosed, passCannyClosed, Imgproc.MORPH_CLOSE, kernel5)

            // Pass 2: Combined Canny + MORPH_CLOSE 5x5 (catches distant/low-contrast sheets)
            val passCombinedClosed = Mat()
            Imgproc.morphologyEx(combinedEdges, passCombinedClosed, Imgproc.MORPH_CLOSE, kernel5)

            // Pass 3: Otsu binary body mask
            val passes = listOf(passCannyClosed, passCombinedClosed, otsuBinary)

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
                    val candidates = contours.take(8)

                    for (contour in candidates) {
                        val candidatePts = extractCandidateQuad(contour, minArea, maxAreaAllowed)
                        if (candidatePts != null) {
                            val score = evaluateDocumentQuality(
                                ordered = candidatePts,
                                gray = morphClosedGray,
                                edgeMask = edgeSupportMask,
                                priorQuad = priorDownscaled,
                                frameW = w,
                                frameH = h,
                                downscaledArea = downscaledArea
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
                passCannyClosed.release()
                passCombinedClosed.release()
            }
        } finally {
            downscaled.release()
            blurred.release()
            morphClosedGray.release()
            claheGray.release()
            cannyClosed.release()
            cannySensitive.release()
            otsuBinary.release()
            combinedEdges.release()
            edgeSupportMask.release()
            kernelClose7.release()
            kernel5.release()
            kernel3.release()
        }

        // Scale-independent quality threshold (0.58) so both distant (5%) and close (95%) papers pass!
        if (bestQuad == null || bestScore < 0.58) return null

        val invScale = 1.0 / scale
        val scaledQuad = bestQuad.map {
            Point(
                (it.x * invScale).coerceIn(0.0, originalWidth),
                (it.y * invScale).coerceIn(0.0, originalHeight)
            )
        }

        return orderPoints(scaledQuad)
    }

    /**
     * Extracts a 4-corner polygon from either the raw contour or its convex hull (to bridge small
     * shadow/finger breaks along an edge), then verifies that the polygon has valid perspective
     * paper geometry. False hulls from random objects will be filtered out by [evaluateDocumentQuality]
     * which checks physical edge support along all 4 sides.
     */
    private fun extractCandidateQuad(
        contour: MatOfPoint,
        minArea: Double,
        maxAreaAllowed: Double
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

            // Check raw contour first (most accurate), then convex hull (bridges small edge gaps)
            val shapes = listOfNotNull(contour, hullContour)
            for (shape in shapes) {
                val shapeArea = Imgproc.contourArea(shape)
                if (shapeArea < minArea || shapeArea > maxAreaAllowed) continue

                val c2f = MatOfPoint2f(*shape.toArray())
                val peri = Imgproc.arcLength(c2f, true)

                for (eps in EPSILONS) {
                    val approx = MatOfPoint2f()
                    Imgproc.approxPolyDP(c2f, approx, eps * peri, true)
                    if (approx.total() == 4L) {
                        val pts = approx.toArray().toList()
                        approx.release()
                        val ordered = orderPoints(pts)

                        val quadMat = MatOfPoint(*ordered.toTypedArray())
                        val isConvex = Imgproc.isContourConvex(quadMat)
                        val quadArea = Imgproc.contourArea(quadMat)
                        quadMat.release()

                        // The 4-point polygon must closely match the shape's area (85%..115%)
                        val fitRatio = shapeArea / quadArea.coerceAtLeast(1.0)
                        if (isConvex && quadArea in minArea..maxAreaAllowed && fitRatio in 0.85..1.15) {
                            if (isValidPaperGeometry(ordered)) {
                                c2f.release()
                                return ordered
                            }
                        }
                    } else {
                        approx.release()
                    }
                }
                c2f.release()
            }
        } finally {
            hullIndices.release()
            hullContour?.release()
        }
        return null
    }

    /**
     * Checks that the 4 ordered points [TL, TR, BR, BL] have realistic perspective-paper proportions
     * at any distance (near or far).
     */
    private fun isValidPaperGeometry(ordered: List<Point>): Boolean {
        if (ordered.size != 4) return false

        val topW = hypot(ordered[1].x - ordered[0].x, ordered[1].y - ordered[0].y)
        val rightH = hypot(ordered[2].x - ordered[1].x, ordered[2].y - ordered[1].y)
        val bottomW = hypot(ordered[2].x - ordered[3].x, ordered[2].y - ordered[3].y)
        val leftH = hypot(ordered[3].x - ordered[0].x, ordered[3].y - ordered[0].y)

        // Allow smaller minSide (20px on 400px image = 5% of frame) so distant papers are accepted
        val minSide = min(min(topW, bottomW), min(leftH, rightH))
        if (minSide < 20.0) return false

        // Opposite sides under perspective cannot differ by more than 1.65x
        val widthRatio = max(topW, bottomW) / min(topW, bottomW).coerceAtLeast(1.0)
        val heightRatio = max(leftH, rightH) / min(leftH, rightH).coerceAtLeast(1.0)
        if (widthRatio > 1.65 || heightRatio > 1.65) return false

        val avgW = (topW + bottomW) * 0.5
        val avgH = (leftH + rightH) * 0.5
        val aspect = avgW / avgH.coerceAtLeast(1.0)
        if (aspect < 0.35 || aspect > 2.85) return false

        // Interior angles in [55°, 125°] to support angled/tilted camera holds
        for (i in 0..3) {
            val prev = ordered[(i + 3) % 4]
            val curr = ordered[i]
            val next = ordered[(i + 1) % 4]
            val angle = angleBetweenDegrees(prev, curr, next)
            if (angle < 55.0 || angle > 125.0) return false
        }

        return true
    }

    /**
     * Computes a scale-independent document confidence score (typically 0.0 .. 1.5+).
     * Because the score is NOT multiplied by raw pixel area, a small distant paper (5% of frame)
     * and a large close-up paper (90% of frame) both achieve ~0.80..1.20 when their edges and
     * contrast are valid!
     */
    private fun evaluateDocumentQuality(
        ordered: List<Point>,
        gray: Mat,
        edgeMask: Mat,
        priorQuad: List<Point>?,
        frameW: Double,
        frameH: Double,
        downscaledArea: Double
    ): Double {
        // Only reject if ALL 4 corners sit on the extreme 1% edge of the camera viewport
        val marginX = frameW * 0.01
        val marginY = frameH * 0.01
        var borderCorners = 0
        for (p in ordered) {
            if (p.x <= marginX || p.x >= frameW - marginX || p.y <= marginY || p.y >= frameH - marginY) {
                borderCorners++
            }
        }
        if (borderCorners == 4) return 0.0

        val quadMat = MatOfPoint(*ordered.toTypedArray())
        val quadArea = Imgproc.contourArea(quadMat)
        quadMat.release()

        // 1. Physical Canny edge support along all 4 sides (rejects imaginary convexHull lines)
        val edgeSupport = measureEdgeSupport(ordered, edgeMask)
        if (edgeSupport < 0.70) return 0.0

        // 2. Interior vs exterior paper brightness / contrast verification
        val contrastScore = measureInteriorVsExteriorBrightness(ordered, gray)
        if (contrastScore <= 0.0) return 0.0

        // 3. Rectangularity check
        val matPt2f = MatOfPoint2f(*ordered.toTypedArray())
        val minRect = Imgproc.minAreaRect(matPt2f)
        matPt2f.release()
        val rectArea = (minRect.size.width * minRect.size.height).coerceAtLeast(1.0)
        val rectangularity = (quadArea / rectArea).coerceIn(0.0, 1.0)
        if (rectangularity < 0.70) return 0.0

        // Gentle preference for larger paper when two real papers are in view (0.85 .. 1.15 factor)
        val areaFraction = (quadArea / downscaledArea).coerceIn(0.045, 0.98)
        val sizeWeight = 0.85 + 0.30 * sqrt(areaFraction)

        // 4. Sticky lock bonus if this quad is the same paper (or zoomed version) as priorQuad
        var lockBonus = 1.0
        if (priorQuad != null && priorQuad.size == 4) {
            val diag = hypot(frameW, frameH)
            val cPriorX = (priorQuad[0].x + priorQuad[1].x + priorQuad[2].x + priorQuad[3].x) * 0.25
            val cPriorY = (priorQuad[0].y + priorQuad[1].y + priorQuad[2].y + priorQuad[3].y) * 0.25
            val cNewX = (ordered[0].x + ordered[1].x + ordered[2].x + ordered[3].x) * 0.25
            val cNewY = (ordered[0].y + ordered[1].y + ordered[2].y + ordered[3].y) * 0.25
            val centerDist = hypot(cNewX - cPriorX, cNewY - cPriorY) / diag
            if (centerDist < 0.12) {
                lockBonus = 1.35
            }
        }

        return edgeSupport * rectangularity * contrastScore * sizeWeight * lockBonus
    }

    /**
     * Samples 20 points along each of the 4 sides of [ordered] in [edgeMask].
     * Every single side must have real edge pixels along >= 58% of its length,
     * and the average across all 4 sides must be >= 70%.
     */
    private fun measureEdgeSupport(ordered: List<Point>, edgeMask: Mat): Double {
        val cols = edgeMask.cols()
        val rows = edgeMask.rows()
        val samplesPerSide = 20
        var totalSupport = 0.0

        for (side in 0..3) {
            val p1 = ordered[side]
            val p2 = ordered[(side + 1) % 4]
            var hits = 0

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
            if (sideRatio < 0.58) return 0.0
            totalSupport += sideRatio
        }

        return totalSupport / 4.0
    }

    /**
     * Verifies that the interior of the candidate quad looks like a document/paper
     * compared to its immediate outer background.
     */
    private fun measureInteriorVsExteriorBrightness(ordered: List<Point>, gray: Mat): Double {
        val cols = gray.cols()
        val rows = gray.rows()
        val cx = (ordered[0].x + ordered[1].x + ordered[2].x + ordered[3].x) * 0.25
        val cy = (ordered[0].y + ordered[1].y + ordered[2].y + ordered[3].y) * 0.25

        var insideSum = 0.0
        var outsideSum = 0.0
        var absDiffSum = 0.0
        var count = 0

        for (side in 0..3) {
            val p1 = ordered[side]
            val p2 = ordered[(side + 1) % 4]
            for (s in 1..8) {
                val t = s.toDouble() / 9.0
                val bx = p1.x + t * (p2.x - p1.x)
                val by = p1.y + t * (p2.y - p1.y)

                val vx = bx - cx
                val vy = by - cy

                val inX = (bx - 0.09 * vx).roundToInt().coerceIn(0, cols - 1)
                val inY = (by - 0.09 * vy).roundToInt().coerceIn(0, rows - 1)

                val outX = (bx + 0.09 * vx).roundToInt().coerceIn(0, cols - 1)
                val outY = (by + 0.09 * vy).roundToInt().coerceIn(0, rows - 1)

                val inVal = gray.get(inY, inX)?.get(0) ?: 0.0
                val outVal = gray.get(outY, outX)?.get(0) ?: 0.0

                insideSum += inVal
                outsideSum += outVal
                absDiffSum += abs(inVal - outVal)
                count++
            }
        }

        if (count == 0) return 0.0
        val meanIn = insideSum / count
        val meanOut = outsideSum / count
        val meanAbsDiff = absDiffSum / count

        // Document interior should not be pitch-dark
        if (meanIn < 80.0) return 0.0

        val diff = meanIn - meanOut
        return when {
            diff >= 14.0 -> 1.15
            diff >= 6.0 -> 1.00
            meanIn >= 135.0 && meanAbsDiff >= 8.0 -> 0.95
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

        val tl = pts.minByOrNull { it.x + it.y } ?: pts[0]
        val br = pts.maxByOrNull { it.x + it.y } ?: pts[2]

        val remaining = pts.filter { it !== tl && it !== br }
        val tr: Point
        val bl: Point
        if (remaining.size == 2) {
            tr = remaining.minByOrNull { it.y - it.x } ?: remaining[0]
            bl = remaining.maxByOrNull { it.y - it.x } ?: remaining[1]
        } else {
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

        val cx = (tl.x + tr.x + br.x + bl.x) / 4.0
        val cy = (tl.y + tr.y + br.y + bl.y) / 4.0

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
