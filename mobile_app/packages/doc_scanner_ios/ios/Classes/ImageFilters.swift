import CoreGraphics
import CoreImage
import Foundation
import Metal
import UIKit

public enum ImageFilters {
  /// Shared Metal-backed CIContext with NSNull workingColorSpace to match OpenCV gamma-space math.
  public static let sharedContext: CIContext = {
    let options: [CIContextOption: Any] = [
      .workingColorSpace: NSNull(),
      .workingFormat: CIFormat.RGBAh,
      .cacheIntermediates: false,
    ]
    if let device = MTLCreateSystemDefaultDevice() {
      return CIContext(mtlDevice: device, options: options)
    }
    return CIContext(options: options)
  }()

  private static let noHandwritingCubeData: Data = {
    let size = 32
    var data = [Float](repeating: 0, count: size * size * size * 4)
    var offset = 0
    for b in 0..<size {
      let bf = Float(b) / Float(size - 1)
      for g in 0..<size {
        let gf = Float(g) / Float(size - 1)
        for r in 0..<size {
          let rf = Float(r) / Float(size - 1)
          let maxC = max(rf, max(gf, bf))
          let minC = min(rf, min(gf, bf))
          let delta = maxC - minC
          let s: Float = maxC == 0 ? 0 : (delta / maxC)
          let v: Float = maxC
          // OpenCV HSV S > 70/255 (~0.2745) and V > 40/255 (~0.1568)
          let isColoredInk = (s > (70.0 / 255.0)) && (v > (40.0 / 255.0))
          let val: Float = isColoredInk ? 1.0 : 0.0
          data[offset] = val
          data[offset + 1] = val
          data[offset + 2] = val
          data[offset + 3] = val
          offset += 4
        }
      }
    }
    return data.withUnsafeBufferPointer { Data(buffer: $0) }
  }()

  public static func runFile(
    inPath: String,
    outPath: String,
    filter: String,
    maxSide: Int = 0
  ) -> Bool {
    return autoreleasepool {
      guard FileManager.default.fileExists(atPath: inPath),
        var src = DocumentDetector.loadUprightCIImage(path: inPath, maxSide: maxSide)
      else {
        return false
      }

      if maxSide > 0 {
        let ext = src.extent
        let longer = max(ext.width, ext.height)
        if longer > CGFloat(maxSide) {
          let scale = CGFloat(maxSide) / longer
          src = src
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .cropped(
              to: CGRect(
                x: 0,
                y: 0,
                width: max(floor(ext.width * scale), 1),
                height: max(floor(ext.height * scale), 1)
              )
            )
        }
      }

      let normalized = normalizeFilterName(filter)
      let output: CIImage
      switch normalized {
      case "original":
        output = src
      case "lighten":
        output = applyLighten(src)
      case "enhance":
        output = applyEnhance(src)
      case "gray":
        output = applyGray(src)
      case "eco":
        output = applyEco(src)
      case "no_handwriting":
        output = applyNoHandwriting(src)
      default:
        output = applyEnhance(src)
      }

      return DocumentDetector.writeJPEG(
        ciImage: output,
        toPath: outPath,
        quality: 0.90,
        context: sharedContext
      )
    }
  }

  private static func normalizeFilterName(_ raw: String) -> String {
    switch raw.lowercased() {
    case "document", "enhance":
      return "enhance"
    case "color", "lighten":
      return "lighten"
    case "grayscale", "gray":
      return "gray"
    case "blackwhite", "eco":
      return "eco"
    case "no_handwriting", "nohandwriting":
      return "no_handwriting"
    case "original":
      return "original"
    default:
      return "enhance"
    }
  }

  /// Background illumination estimation + division: downscale ~400px -> dilate -> blur -> upscale -> divide
  private static func flatten(_ src: CIImage) -> CIImage {
    let ext = src.extent
    let longer = max(ext.width, ext.height)
    let targetLongSide: CGFloat = 400.0
    let scale = longer > targetLongSide ? (targetLongSide / longer) : 1.0

    var small = src
    if scale < 1.0 {
      small = src.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
    let smallExt = small.extent

    // Morphological dilation (radius 3) + Gaussian blur (~10) standing in for medianBlur 21
    var bg = small.clampedToExtent()
    if let morph = CIFilter(name: "CIMorphologyMaximum") {
      morph.setValue(bg, forKey: kCIInputImageKey)
      morph.setValue(3.0, forKey: kCIInputRadiusKey)
      if let out = morph.outputImage {
        bg = out
      }
    }
    if let blur = CIFilter(name: "CIGaussianBlur") {
      blur.setValue(bg, forKey: kCIInputImageKey)
      blur.setValue(10.0, forKey: kCIInputRadiusKey)
      if let out = blur.outputImage {
        bg = out
      }
    }
    bg = bg.cropped(to: smallExt)

    if scale < 1.0 {
      let sx = ext.width / max(smallExt.width, 1)
      let sy = ext.height / max(smallExt.height, 1)
      bg = bg.transformed(by: CGAffineTransform(scaleX: sx, y: sy)).cropped(to: ext)
    }

    // CIDivideBlendMode computes inputBackgroundImage / inputImage (paper becomes 1.0, ink stays dark)
    if let divide = CIFilter(name: "CIDivideBlendMode") {
      divide.setValue(bg, forKey: kCIInputImageKey)
      divide.setValue(src, forKey: kCIInputBackgroundImageKey)
      if let out = divide.outputImage?.cropped(to: ext) {
        return out
      }
    }
    return src
  }

  /// Levels transform: maps [black/255 .. white/255] to [0 .. 1] with gamma power.
  private static func applyLevels(
    _ img: CIImage,
    black: CGFloat,
    white: CGFloat,
    gamma: CGFloat
  ) -> CIImage {
    let ext = img.extent
    let scale = 255.0 / max(white - black, 1.0)
    let bias = -black / max(white - black, 1.0)

    var current = img
    if let matrix = CIFilter(name: "CIColorMatrix") {
      matrix.setValue(current, forKey: kCIInputImageKey)
      matrix.setValue(CIVector(x: scale, y: 0, z: 0, w: 0), forKey: "inputRVector")
      matrix.setValue(CIVector(x: 0, y: scale, z: 0, w: 0), forKey: "inputGVector")
      matrix.setValue(CIVector(x: 0, y: 0, z: scale, w: 0), forKey: "inputBVector")
      matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
      matrix.setValue(CIVector(x: bias, y: bias, z: bias, w: 0), forKey: "inputBiasVector")
      if let out = matrix.outputImage {
        current = out
      }
    }

    if let clamp = CIFilter(name: "CIColorClamp") {
      clamp.setValue(current, forKey: kCIInputImageKey)
      clamp.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputMinComponents")
      clamp.setValue(CIVector(x: 1, y: 1, z: 1, w: 1), forKey: "inputMaxComponents")
      if let out = clamp.outputImage {
        current = out
      }
    }

    if abs(gamma - 1.0) > 0.001, let gammaFilter = CIFilter(name: "CIGammaAdjust") {
      gammaFilter.setValue(current, forKey: kCIInputImageKey)
      gammaFilter.setValue(gamma, forKey: "inputPower")
      if let out = gammaFilter.outputImage {
        current = out
      }
    }

    return current.cropped(to: ext)
  }

  /// Lighten: Gamma 0.7 + contrast 1.08 (matches Android applyLighten).
  private static func applyLighten(_ src: CIImage) -> CIImage {
    let ext = src.extent
    var current = src
    if let gammaFilter = CIFilter(name: "CIGammaAdjust") {
      gammaFilter.setValue(current, forKey: kCIInputImageKey)
      gammaFilter.setValue(0.7, forKey: "inputPower")
      if let out = gammaFilter.outputImage {
        current = out
      }
    }
    if let controls = CIFilter(name: "CIColorControls") {
      controls.setValue(current, forKey: kCIInputImageKey)
      controls.setValue(1.08, forKey: kCIInputContrastKey)
      if let out = controls.outputImage {
        current = out
      }
    }
    return current.cropped(to: ext)
  }

  /// Enhance: flatten -> levels (35..225, gamma 1.1) -> unsharp mask (sigma 2.0, intensity 0.6).
  private static func applyEnhance(_ src: CIImage) -> CIImage {
    let ext = src.extent
    let flattened = flatten(src)
    var current = applyLevels(flattened, black: 35.0, white: 225.0, gamma: 1.1)
    if let unsharp = CIFilter(name: "CIUnsharpMask") {
      unsharp.setValue(current, forKey: kCIInputImageKey)
      unsharp.setValue(2.0, forKey: kCIInputRadiusKey)
      unsharp.setValue(0.6, forKey: kCIInputIntensityKey)
      if let out = unsharp.outputImage {
        current = out
      }
    }
    return current.cropped(to: ext)
  }

  /// Gray: flatten -> saturation 0 -> levels (40..220, gamma 1/1.1).
  private static func applyGray(_ src: CIImage) -> CIImage {
    let ext = src.extent
    var current = flatten(src)
    if let controls = CIFilter(name: "CIColorControls") {
      controls.setValue(current, forKey: kCIInputImageKey)
      controls.setValue(0.0, forKey: kCIInputSaturationKey)
      if let out = controls.outputImage {
        current = out
      }
    }
    current = applyLevels(current, black: 40.0, white: 220.0, gamma: 1.0 / 1.1)
    return current.cropped(to: ext)
  }

  /// Eco: adaptive Gaussian threshold mirroring OpenCV adaptiveThreshold(GAUSSIAN_C, blockSize, C=12).
  private static func applyEco(_ src: CIImage) -> CIImage {
    let ext = src.extent
    var gray = flatten(src)
    if let controls = CIFilter(name: "CIColorControls") {
      controls.setValue(gray, forKey: kCIInputImageKey)
      controls.setValue(0.0, forKey: kCIInputSaturationKey)
      if let out = controls.outputImage {
        gray = out.cropped(to: ext)
      }
    }

    let minSide = Int(min(ext.width, ext.height))
    let blockSize = max((minSide / 30) | 1, 3)
    let sigma = 0.3 * (Double(blockSize - 1) * 0.5 - 1.0) + 0.8

    var blurred = gray.clampedToExtent()
    if let blur = CIFilter(name: "CIGaussianBlur") {
      blur.setValue(blurred, forKey: kCIInputImageKey)
      blur.setValue(max(sigma, 1.0), forKey: kCIInputRadiusKey)
      if let out = blur.outputImage {
        blurred = out.cropped(to: ext)
      }
    }

    // Compute diff = gray - blurred + 12/255 + 0.5, then threshold at 0.5
    // Since Core Image CISubtractBlendMode is inputImage - inputBackgroundImage,
    // we add bias (0.5 + 12.0/255.0) to gray first, then subtract blurred, and threshold at 0.5.
    let offset = CGFloat(0.5 + (12.0 / 255.0))
    var shiftedGray = gray
    if let matrix = CIFilter(name: "CIColorMatrix") {
      matrix.setValue(gray, forKey: kCIInputImageKey)
      matrix.setValue(CIVector(x: offset, y: offset, z: offset, w: 0), forKey: "inputBiasVector")
      if let out = matrix.outputImage {
        shiftedGray = out.cropped(to: ext)
      }
    }

    var diff = shiftedGray
    if let sub = CIFilter(name: "CISubtractBlendMode") {
      sub.setValue(shiftedGray, forKey: kCIInputImageKey)
      sub.setValue(blurred, forKey: kCIInputBackgroundImageKey)
      if let out = sub.outputImage {
        diff = out.cropped(to: ext)
      }
    }

    if let thresh = CIFilter(name: "CIColorThreshold") {
      thresh.setValue(diff, forKey: kCIInputImageKey)
      thresh.setValue(0.5, forKey: "inputThreshold")
      if let out = thresh.outputImage {
        return out.cropped(to: ext)
      }
    }
    return diff.cropped(to: ext)
  }

  /// No Handwriting: enhance -> 32^3 HSV mask (S>70/255, V>40/255) -> dilate -> composite white.
  private static func applyNoHandwriting(_ src: CIImage) -> CIImage {
    let ext = src.extent
    let enhanced = applyEnhance(src)

    guard let cube = CIFilter(name: "CIColorCube") else {
      return enhanced
    }
    cube.setValue(enhanced, forKey: kCIInputImageKey)
    cube.setValue(32, forKey: "inputCubeDimension")
    cube.setValue(noHandwritingCubeData, forKey: "inputCubeData")
    guard var mask = cube.outputImage?.cropped(to: ext) else {
      return enhanced
    }

    if let dilate = CIFilter(name: "CIMorphologyMaximum") {
      dilate.setValue(mask.clampedToExtent(), forKey: kCIInputImageKey)
      dilate.setValue(2.0, forKey: kCIInputRadiusKey)
      if let out = dilate.outputImage {
        mask = out.cropped(to: ext)
      }
    }

    let whiteImage = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: ext)
    if let blend = CIFilter(name: "CIBlendWithMask") {
      blend.setValue(whiteImage, forKey: kCIInputImageKey)
      blend.setValue(enhanced, forKey: kCIInputBackgroundImageKey)
      blend.setValue(mask, forKey: kCIInputMaskImageKey)
      if let out = blend.outputImage {
        return out.cropped(to: ext)
      }
    }
    return enhanced
  }
}
