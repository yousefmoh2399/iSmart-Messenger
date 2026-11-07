import Flutter
import UIKit

public class DocScannerIosPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "ismart/doc_scanner", binaryMessenger: registrar.messenger())
    let instance = DocScannerIosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startScan", "warp", "applyFilter", "rotateLeft":
      // Stub implementation for Step 1 - to be fully implemented in Steps 2-5
      result(FlutterMethodNotImplemented)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
