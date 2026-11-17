import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UIKit
import Vision
import os.log

public enum ScannerOpStatus {
  case success
  case readFailed(String)
  case writeFailed(String)
  case processError(String)
}

public enum DocumentDetector {
  public static let log = OSLog(subsystem: "com.ismart.docscanner", category: "DocScan")

  public static func logInfo(_ message: String) {
    os_log("%{public}@", log: log, type: .info, message)
    print("[DocScan] \(message)")
  }

  /// Detects a 4-corner document quadrilateral in normalized Top-Left coordinates [TL, TR, BR, BL].
  public static func findQuad(
    in pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation = .right
  ) -> [CGPoint]? {
    let request = VNDetectDocumentSegmentationRequest()
    let handler = VNImageRequestHandler(
      cvPixelBuffer: pixelBuffer,
      orientation: orientation,
      options: [:]
    )
    do {
      try handler.perform([request])
      guard let obs = request.results?.first as? VNRectangleObservation else {
        return nil
      }
      return validateAndOrderObservation(obs)
    } catch {
      return nil
    }
  }

  /// Detects a 4-corner document quadrilateral in an upright CGImage.
  public static func findQuad(in cgImage: CGImage) -> [CGPoint]? {
    let request = VNDetectDocumentSegmentationRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
    do {
      try handler.perform([request])
      guard let obs = request.results?.first as? VNRectangleObservation else {
        return nil
      }
      return validateAndOrderObservation(obs)
    } catch {
      return nil
    }
  }

  /// Detects a 4-corner document quadrilateral in a file on disk using an ~800px upright thumbnail.
  public static func findQuadInFile(path: String) -> [CGPoint]? {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      return nil
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 800,
    ]
    guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
      return nil
    }
    return findQuad(in: thumb)
  }

  public static func defaultInsetQuad() -> [CGPoint] {
    return [
      CGPoint(x: 0.05, y: 0.05),
      CGPoint(x: 0.95, y: 0.05),
      CGPoint(x: 0.95, y: 0.95),
      CGPoint(x: 0.05, y: 0.95),
    ]
  }

  public static func flattenQuad(_ pts: [CGPoint]) -> [Double] {
    guard pts.count == 4 else {
      return [0.05, 0.05, 0.95, 0.05, 0.95, 0.95, 0.05, 0.95]
    }
    return [
      Double(pts[0].x), Double(pts[0].y),
      Double(pts[1].x), Double(pts[1].y),
      Double(pts[2].x), Double(pts[2].y),
      Double(pts[3].x), Double(pts[3].y),
    ]
  }

  private static func validateAndOrderObservation(_ obs: VNRectangleObservation) -> [CGPoint]? {
    // Convert Vision bottom-left origin to Top-Left origin (y = 1.0 - y)
    let rawPoints = [
      CGPoint(x: obs.topLeft.x, y: 1.0 - obs.topLeft.y),
      CGPoint(x: obs.topRight.x, y: 1.0 - obs.topRight.y),
      CGPoint(x: obs.bottomRight.x, y: 1.0 - obs.bottomRight.y),
      CGPoint(x: obs.bottomLeft.x, y: 1.0 - obs.bottomLeft.y),
    ]
    let ordered = orderPoints(rawPoints)
    let area = polygonArea(ordered)
    guard area >= 0.15 && area <= 0.97 else {
      return nil
    }
    guard isConvexQuad(ordered) else {
      return nil
    }
    return ordered
  }

  /// Orders 4 points to [TL, TR, BR, BL] using sum (x+y) and difference (y-x), identical to Android.
  public static func orderPoints(_ pts: [CGPoint]) -> [CGPoint] {
    guard pts.count == 4 else { return pts }
    let indexed = Array(pts.enumerated())
    let tlEntry = indexed.min(by: { ($0.element.x + $0.element.y) < ($1.element.x + $1.element.y) })!
    let brEntry = indexed.max(by: { ($0.element.x + $0.element.y) < ($1.element.x + $1.element.y) })!
    let remaining = indexed.filter { $0.offset != tlEntry.offset && $0.offset != brEntry.offset }
    let tr: CGPoint
    let bl: CGPoint
    if remaining.count == 2 {
      tr = remaining.min(by: { ($0.element.y - $0.element.x) < ($1.element.y - $1.element.x) })!.element
      bl = remaining.max(by: { ($0.element.y - $0.element.x) < ($1.element.y - $1.element.x) })!.element
    } else {
      tr = indexed.min(by: { ($0.element.y - $0.element.x) < ($1.element.y - $1.element.x) })!.element
      bl = indexed.max(by: { ($0.element.y - $0.element.x) < ($1.element.y - $1.element.x) })!.element
    }
    return [tlEntry.element, tr, brEntry.element, bl]
  }

  private static func polygonArea(_ pts: [CGPoint]) -> CGFloat {
    guard pts.count == 4 else { return 0 }
    var sum: CGFloat = 0
    for i in 0..<4 {
      let p1 = pts[i]
      let p2 = pts[(i + 1) % 4]
      sum += (p1.x * p2.y) - (p2.x * p1.y)
    }
    return abs(sum) * 0.5
  }

  private static func isConvexQuad(_ pts: [CGPoint]) -> Bool {
    guard pts.count == 4 else { return false }
    var sign: Bool?
    for i in 0..<4 {
      let a = pts[i]
      let b = pts[(i + 1) % 4]
      let c = pts[(i + 2) % 4]
      let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
      if abs(cross) < 1e-6 { return false }
      let currentSign = cross > 0
      if let s = sign {
        if s != currentSign { return false }
      } else {
        sign = currentSign
      }
    }
    return true
  }

  /// Reads upright dimensions and, if a raw camera capture is landscape without an orientation tag,
  /// fixes it via lossless metadata rewrite (CGImageDestinationCopyImageSource).
  public static func ensureUprightAndReadDimensions(
    path: String,
    isPortraitCameraCapture: Bool = false
  ) -> (width: Int, height: Int)? {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
      let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
      let w = props[kCGImagePropertyPixelWidth] as? Int,
      let h = props[kCGImagePropertyPixelHeight] as? Int
    else {
      return nil
    }

    let rawOrientation = props[kCGImagePropertyOrientation] as? UInt32
    if isPortraitCameraCapture && w > h && (rawOrientation == nil || rawOrientation == 1) {
      // Lossless metadata rewrite setting orientation = 6 (.right) so EXIF-honoring readers see it upright
      let tempURL = url.deletingLastPathComponent().appendingPathComponent("tmp_\(UUID().uuidString).jpg")
      if let dest = CGImageDestinationCreateWithURL(
        tempURL as CFURL,
        CGImageSourceGetType(src) ?? ("public.jpeg" as CFString),
        1,
        nil
      ) {
        let options: [CFString: Any] = [
          kCGImagePropertyOrientation: 6
        ]
        var err: Unmanaged<CFError>?
        if CGImageDestinationCopyImageSource(dest, src, options as CFDictionary, &err) {
          _ = try? FileManager.default.replaceItemAt(url, withItemAt: tempURL)
          return (width: h, height: w)
        } else {
          try? FileManager.default.removeItem(at: tempURL)
        }
      }
    }

    let orientation = rawOrientation ?? 1
    if orientation >= 5 && orientation <= 8 {
      return (width: h, height: w)
    }
    return (width: w, height: h)
  }

  /// Reads upright pixel width and height of an image file without decoding full pixels.
  public static func readUprightDimensions(path: String) -> (width: Int, height: Int)? {
    return ensureUprightAndReadDimensions(path: path, isPortraitCameraCapture: false)
  }

  /// Loads an upright CIImage, optionally decoding at half/reduced resolution when maxSide > 0 and source >= 2*maxSide.
  public static func loadUprightCIImage(path: String, maxSide: Int = 0) -> CIImage? {
    let url = URL(fileURLWithPath: path)
    if maxSide > 0, let dims = readUprightDimensions(path: path) {
      let longer = max(dims.width, dims.height)
      if longer >= 2 * maxSide,
        let src = CGImageSourceCreateWithURL(url as CFURL, nil)
      {
        let targetThumb = max(longer / 2, maxSide)
        let opts: [CFString: Any] = [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: targetThumb,
        ]
        if let cgThumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
          return CIImage(cgImage: cgThumb)
        }
      }
    }
    guard let ci = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
      return nil
    }
    let ext = ci.extent
    if ext.origin.x != 0 || ext.origin.y != 0 {
      return ci.transformed(by: CGAffineTransform(translationX: -ext.origin.x, y: -ext.origin.y))
    }
    return ci
  }

  /// Warps the quadrilateral in `path` and writes an upright JPEG (q0.95, EXIF orientation 1) to `outPath`.
  public static func warp(
    path: String,
    corners: [Double],
    outPath: String,
    maxSide: Int = 0,
    quarterTurns: Int = 0,
    context: CIContext
  ) -> ScannerOpStatus {
    return autoreleasepool {
      let startTime = CACurrentMediaTime()
      guard corners.count == 8 else {
        return .processError("corners must contain 8 doubles")
      }
      guard let srcImage = loadUprightCIImage(path: path, maxSide: maxSide) else {
        return .readFailed("Failed to read source image at \(path)")
      }
      let w = Double(srcImage.extent.width)
      let h = Double(srcImage.extent.height)
      guard w > 1 && h > 1 else {
        return .readFailed("Invalid image dimensions \(w)x\(h)")
      }

      // Input corners in pixel space (Top-Left origin)
      let tl = CGPoint(x: corners[0] * w, y: corners[1] * h)
      let tr = CGPoint(x: corners[2] * w, y: corners[3] * h)
      let br = CGPoint(x: corners[4] * w, y: corners[5] * h)
      let bl = CGPoint(x: corners[6] * w, y: corners[7] * h)

      let widthA = hypot(br.x - bl.x, br.y - bl.y)
      let widthB = hypot(tr.x - tl.x, tr.y - tl.y)
      var maxWidth = max(Int(max(widthA, widthB)), 100)

      let heightA = hypot(tr.x - br.x, tr.y - br.y)
      let heightB = hypot(tl.x - bl.x, tl.y - bl.y)
      var maxHeight = max(Int(max(heightA, heightB)), 100)

      if maxSide > 0 {
        let longer = max(maxWidth, maxHeight)
        if longer > maxSide {
          let scale = Double(maxSide) / Double(longer)
          maxWidth = max(Int(Double(maxWidth) * scale), 50)
          maxHeight = max(Int(Double(maxHeight) * scale), 50)
        }
      }

      // Shrink 0.5% toward centroid to remove border slivers
      let cx = (tl.x + tr.x + br.x + bl.x) * 0.25
      let cy = (tl.y + tr.y + br.y + bl.y) * 0.25
      let inset: CGFloat = 0.005
      func shrink(_ p: CGPoint) -> CGPoint {
        return CGPoint(
          x: p.x + inset * (cx - p.x),
          y: p.y + inset * (cy - p.y)
        )
      }

      // Convert Top-Left pixel coords to Core Image Bottom-Left coords: ciY = h - y
      func toCI(_ p: CGPoint) -> CIVector {
        let s = shrink(p)
        return CIVector(x: s.x, y: CGFloat(h) - s.y)
      }

      guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
        return .processError("CIPerspectiveCorrection filter unavailable")
      }
      filter.setValue(srcImage, forKey: kCIInputImageKey)
      filter.setValue(toCI(tl), forKey: "inputTopLeft")
      filter.setValue(toCI(tr), forKey: "inputTopRight")
      filter.setValue(toCI(br), forKey: "inputBottomRight")
      filter.setValue(toCI(bl), forKey: "inputBottomLeft")

      guard var warped = filter.outputImage else {
        return .processError("Perspective transform produced nil output")
      }

      // Normalize origin to (0,0) and scale to exact (maxWidth, maxHeight)
      let wExt = warped.extent
      if wExt.width > 0 && wExt.height > 0 {
        warped = warped.transformed(
          by: CGAffineTransform(translationX: -wExt.origin.x, y: -wExt.origin.y)
        )
        let sx = CGFloat(maxWidth) / wExt.width
        let sy = CGFloat(maxHeight) / wExt.height
        warped = warped
          .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
          .cropped(to: CGRect(x: 0, y: 0, width: maxWidth, height: maxHeight))
      }

      // Apply quarterTurns counter-clockwise if requested
      let turns = ((quarterTurns % 4) + 4) % 4
      if turns != 0 {
        switch turns {
        case 1:
          warped = warped.oriented(.left)
        case 2:
          warped = warped.oriented(.down)
        case 3:
          warped = warped.oriented(.right)
        default:
          break
        }
        let rExt = warped.extent
        warped = warped.transformed(
          by: CGAffineTransform(translationX: -rExt.origin.x, y: -rExt.origin.y)
        )
      }

      let written = writeJPEG(ciImage: warped, toPath: outPath, quality: 0.95, context: context)
      let elapsedMs = Int((CACurrentMediaTime() - startTime) * 1000.0)
      logInfo("Warp time (transform + write): \(elapsedMs)ms -> \(outPath) (maxSide=\(maxSide), quarterTurns=\(quarterTurns))")
      return written ? .success : .writeFailed("Failed to write warped JPEG to \(outPath)")
    }
  }

  /// Rotates the image 90 degrees counter-clockwise and writes upright JPEG (q0.95) to `outPath`.
  public static func rotateLeft(
    path: String,
    outPath: String,
    context: CIContext
  ) -> ScannerOpStatus {
    return autoreleasepool {
      guard let srcImage = loadUprightCIImage(path: path) else {
        return .readFailed("Failed to read image at \(path)")
      }
      var rotated = srcImage.oriented(.left)
      let ext = rotated.extent
      rotated = rotated.transformed(
        by: CGAffineTransform(translationX: -ext.origin.x, y: -ext.origin.y)
      )
      let written = writeJPEG(ciImage: rotated, toPath: outPath, quality: 0.95, context: context)
      return written ? .success : .writeFailed("Failed to write rotated JPEG to \(outPath)")
    }
  }

  /// Composites a PNG signature onto a page JPEG and returns JPEG bytes capped at `maxSide`.
  public static func compositeSignature(
    pagePath: String,
    signatureBytes: Data,
    relX: Double,
    relY: Double,
    relW: Double,
    maxSide: Int = 2048
  ) -> Data? {
    return autoreleasepool {
      let startTime = CACurrentMediaTime()
      guard let rawPage = UIImage(contentsOfFile: pagePath),
        let sigImage = UIImage(data: signatureBytes)
      else {
        return nil
      }
      let pageSize = rawPage.size
      guard pageSize.width > 0 && pageSize.height > 0 else { return nil }

      let longerSide = max(pageSize.width, pageSize.height)
      var targetSize = pageSize
      if maxSide > 0 && longerSide > CGFloat(maxSide) {
        let scale = CGFloat(maxSide) / longerSide
        targetSize = CGSize(
          width: max(floor(pageSize.width * scale), 1),
          height: max(floor(pageSize.height * scale), 1)
        )
      }

      let format = UIGraphicsImageRendererFormat()
      format.scale = 1.0
      format.opaque = true
      let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

      let rendered = renderer.image { _ in
        rawPage.draw(in: CGRect(origin: .zero, size: targetSize))

        let targetW = min(max(targetSize.width * CGFloat(relW), 10), targetSize.width)
        let aspect = sigImage.size.height / max(sigImage.size.width, 1)
        let targetH = min(max(targetW * aspect, 1), targetSize.height)
        let offsetX = min(
          max(targetSize.width * CGFloat(relX), 0),
          max(targetSize.width - targetW, 0)
        )
        let offsetY = min(
          max(targetSize.height * CGFloat(relY), 0),
          max(targetSize.height - targetH, 0)
        )
        sigImage.draw(in: CGRect(x: offsetX, y: offsetY, width: targetW, height: targetH))
      }

      let outData = rendered.jpegData(compressionQuality: 0.92)
      let elapsedMs = Int((CACurrentMediaTime() - startTime) * 1000.0)
      logInfo("compositeSignature completed in \(elapsedMs)ms (\(outData?.count ?? 0) bytes)")
      return outData
    }
  }

  /// Writes a CIImage as an sRGB JPEG with upright EXIF orientation 1.
  public static func writeJPEG(
    ciImage: CIImage,
    toPath outPath: String,
    quality: Float,
    context: CIContext
  ) -> Bool {
    let outURL = URL(fileURLWithPath: outPath)
    let parentDir = outURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let cgImage = context.createCGImage(
      ciImage,
      from: ciImage.extent.integral,
      format: .RGBA8,
      colorSpace: colorSpace
    ) else {
      return false
    }

    guard let dest = CGImageDestinationCreateWithURL(
      outURL as CFURL,
      "public.jpeg" as CFString,
      1,
      nil
    ) else {
      return false
    }

    let props: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: quality,
      kCGImagePropertyOrientation: 1,
    ]
    CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
    return CGImageDestinationFinalize(dest)
  }
}
