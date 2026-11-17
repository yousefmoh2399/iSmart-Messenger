import Flutter
import UIKit

public class DocScannerIosPlugin: NSObject, FlutterPlugin {
  private let workerQueue = DispatchQueue(
    label: "ismart.doc_scanner.worker",
    qos: .userInitiated,
    attributes: .concurrent
  )
  private let opSemaphore = DispatchSemaphore(value: 2)
  private var pendingScanResult: FlutterResult?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "ismart/doc_scanner",
      binaryMessenger: registrar.messenger()
    )
    let instance = DocScannerIosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startScan":
      handleStartScan(call, result: result)
    case "warp":
      handleWarp(call, result: result)
    case "applyFilter":
      handleApplyFilter(call, result: result)
    case "rotateLeft":
      handleRotateLeft(call, result: result)
    case "compositeSignature":
      handleCompositeSignature(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleStartScan(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if pendingScanResult != nil {
      result(FlutterError(code: "SCANNER_BUSY", message: "A scan is already in progress", details: nil))
      return
    }
    let args = call.arguments as? [String: Any]
    let destDir = (args?["destDir"] as? String) ?? NSTemporaryDirectory()
    let batch = (args?["batch"] as? Bool) ?? false

    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      guard let topVC = Self.topViewController() else {
        result(FlutterError(code: "LAUNCH_FAILED", message: "Could not find top view controller", details: nil))
        return
      }
      self.pendingScanResult = result
      let scannerVC = ScannerViewController(
        destinationDir: destDir,
        isBatchMode: batch
      ) { [weak self] items, isBatch in
        guard let self = self, let pending = self.pendingScanResult else { return }
        self.pendingScanResult = nil
        guard let items = items, !items.isEmpty else {
          pending(nil)
          return
        }
        if isBatch || items.count > 1 {
          let mapped = items.map { $0.toMap() }
          pending([
            "batch": true,
            "items": mapped,
          ])
        } else {
          var single = items[0].toMap()
          single["batch"] = false
          pending(single)
        }
      }
      topVC.present(scannerVC, animated: true)
    }
  }

  private func handleWarp(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let path = args["path"] as? String,
      !path.isEmpty,
      let rawCorners = args["corners"] as? [NSNumber],
      rawCorners.count == 8,
      let outPath = args["outPath"] as? String,
      !outPath.isEmpty
    else {
      result(FlutterError(code: "INVALID_ARGS", message: "path, corners (8 items), and outPath are required", details: nil))
      return
    }
    let corners = rawCorners.map { $0.doubleValue }
    let maxSide = (args["maxSide"] as? NSNumber)?.intValue ?? 0
    let quarterTurns = (args["quarterTurns"] as? NSNumber)?.intValue ?? 0

    workerQueue.async { [weak self] in
      guard let self = self else { return }
      self.opSemaphore.wait()
      defer { self.opSemaphore.signal() }

      let status = DocumentDetector.warp(
        path: path,
        corners: corners,
        outPath: outPath,
        maxSide: maxSide,
        quarterTurns: quarterTurns,
        context: ImageFilters.sharedContext
      )
      DispatchQueue.main.async {
        switch status {
        case .success:
          result(outPath)
        case .readFailed(let msg):
          result(FlutterError(code: "READ_FAILED", message: msg, details: nil))
        case .writeFailed(let msg):
          result(FlutterError(code: "WRITE_FAILED", message: msg, details: nil))
        case .processError(let msg):
          result(FlutterError(code: "WARP_ERROR", message: msg, details: nil))
        }
      }
    }
  }

  private func handleApplyFilter(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let path = args["path"] as? String,
      !path.isEmpty,
      let outPath = args["outPath"] as? String,
      !outPath.isEmpty
    else {
      result(FlutterError(code: "INVALID_ARGS", message: "path and outPath are required", details: nil))
      return
    }
    let filter = (args["filter"] as? String) ?? "enhance"
    let maxSide = (args["maxSide"] as? NSNumber)?.intValue ?? 0

    workerQueue.async { [weak self] in
      guard let self = self else { return }
      self.opSemaphore.wait()
      defer { self.opSemaphore.signal() }

      let ok = ImageFilters.runFile(
        inPath: path,
        outPath: outPath,
        filter: filter,
        maxSide: maxSide
      )
      DispatchQueue.main.async {
        if ok {
          result(outPath)
        } else {
          result(FlutterError(code: "FILTER_FAILED", message: "Failed to apply filter \(filter)", details: nil))
        }
      }
    }
  }

  private func handleRotateLeft(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let path = args["path"] as? String,
      !path.isEmpty,
      let outPath = args["outPath"] as? String,
      !outPath.isEmpty
    else {
      result(FlutterError(code: "INVALID_ARGS", message: "path and outPath are required", details: nil))
      return
    }

    workerQueue.async { [weak self] in
      guard let self = self else { return }
      self.opSemaphore.wait()
      defer { self.opSemaphore.signal() }

      let status = DocumentDetector.rotateLeft(
        path: path,
        outPath: outPath,
        context: ImageFilters.sharedContext
      )
      DispatchQueue.main.async {
        switch status {
        case .success:
          result(outPath)
        case .readFailed(let msg):
          result(FlutterError(code: "READ_FAILED", message: msg, details: nil))
        case .writeFailed(let msg):
          result(FlutterError(code: "WRITE_FAILED", message: msg, details: nil))
        case .processError(let msg):
          result(FlutterError(code: "ROTATE_ERROR", message: msg, details: nil))
        }
      }
    }
  }

  private func handleCompositeSignature(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let pagePath = args["pagePath"] as? String,
      !pagePath.isEmpty,
      let sigTypedData = args["signatureBytes"] as? FlutterStandardTypedData
    else {
      result(FlutterError(code: "INVALID_ARGS", message: "pagePath and signatureBytes are required", details: nil))
      return
    }
    let relX = (args["relX"] as? NSNumber)?.doubleValue ?? 0.05
    let relY = (args["relY"] as? NSNumber)?.doubleValue ?? 0.70
    let relW = (args["relW"] as? NSNumber)?.doubleValue ?? 0.40
    let maxSide = (args["maxSide"] as? NSNumber)?.intValue ?? 2048

    workerQueue.async {
      guard let outData = DocumentDetector.compositeSignature(
        pagePath: pagePath,
        signatureBytes: sigTypedData.data,
        relX: relX,
        relY: relY,
        relW: relW,
        maxSide: maxSide
      ) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "COMPOSITE_ERROR", message: "Failed to composite signature", details: nil))
        }
        return
      }
      DispatchQueue.main.async {
        result(FlutterStandardTypedData(bytes: outData))
      }
    }
  }

  private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
    let root: UIViewController?
    if let base = base {
      root = base
    } else if #available(iOS 13.0, *) {
      root = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow && $0.accessibilityIdentifier != "EasySplashOverlay" }?
        .rootViewController
        ?? UIApplication.shared.connectedScenes
          .compactMap { $0 as? UIWindowScene }
          .flatMap { $0.windows }
          .first { $0.accessibilityIdentifier != "EasySplashOverlay" }?
          .rootViewController
    } else {
      root = UIApplication.shared.keyWindow?.rootViewController
    }

    if let nav = root as? UINavigationController {
      return topViewController(base: nav.visibleViewController)
    }
    if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
      return topViewController(base: selected)
    }
    if let presented = root?.presentedViewController {
      return topViewController(base: presented)
    }
    return root
  }
}
