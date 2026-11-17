import AVFoundation
import CoreImage
import ImageIO
import PhotosUI
import UIKit
import Vision
import os.log

public struct CapturedScanItem {
  public let path: String
  public let corners: [Double]
  public let width: Int
  public let height: Int

  public func toMap() -> [String: Any] {
    return [
      "path": path,
      "corners": corners,
      "width": width,
      "height": height,
    ]
  }
}

public final class ScannerViewController: UIViewController {
  private let destinationDir: String
  private var isBatchMode: Bool
  private let onFinish: (([CapturedScanItem]?, Bool) -> Void)
  private var hasFinished = false

  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "ismart.doc_scanner.session")
  private let videoOutputQueue = DispatchQueue(label: "ismart.doc_scanner.video")
  private let photoOutput = AVCapturePhotoOutput()
  private var videoDevice: AVCaptureDevice?

  private let previewContainer = UIView()
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private let quadLayer = CAShapeLayer()

  private let topBar = UIView()
  private let closeButton = UIButton(type: .system)
  private let modeToggleButton = UIButton(type: .system)
  private let torchButton = UIButton(type: .system)

  private let bottomBar = UIView()
  private let galleryButton = UIButton(type: .system)
  private let shutterButton = UIButton(type: .custom)
  private let doneButton = UIButton(type: .system)

  private var isTorchOn = false
  private var isCapturing = false
  private var lastShutterTime: TimeInterval = 0
  private var shutterTapTimestamp: TimeInterval = 0
  private var snappedCornersAtTap: [CGPoint]?

  private var batchItems: [CapturedScanItem] = []

  // Live quad smoothing state
  private var isAnalyzingFrame = false
  private var frameCounter = 0
  private var analyzeEveryNthFrame = 1
  private var analyzerCount = 0
  private var analyzerTotalMs: Double = 0
  private var latestQuad: [CGPoint]?
  private var previousQuad: [CGPoint]?
  private var missedFrameCount = 0

  public init(
    destinationDir: String,
    isBatchMode: Bool,
    onFinish: @escaping ([CapturedScanItem]?, Bool) -> Void
  ) {
    self.destinationDir = destinationDir
    self.isBatchMode = isBatchMode
    self.onFinish = onFinish
    super.init(nibName: nil, bundle: nil)
    self.modalPresentationStyle = .fullScreen
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    return .portrait
  }

  public override var shouldAutorotate: Bool {
    return false
  }

  public override var prefersStatusBarHidden: Bool {
    return true
  }

  public override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    setupUI()
    setupNotifications()
    checkPermissionAndStartSession()
  }

  public override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let bounds = view.bounds
    let targetRatio: CGFloat = 3.0 / 4.0
    var containerW = bounds.width
    var containerH = containerW / targetRatio
    if containerH > bounds.height {
      containerH = bounds.height
      containerW = containerH * targetRatio
    }
    previewContainer.frame = CGRect(
      x: (bounds.width - containerW) * 0.5,
      y: (bounds.height - containerH) * 0.5,
      width: containerW,
      height: containerH
    )
    previewLayer?.frame = previewContainer.bounds
    quadLayer.frame = previewContainer.bounds
  }

  public override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      if self.session.isRunning {
        self.session.stopRunning()
      }
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private func setupUI() {
    previewContainer.backgroundColor = .black
    previewContainer.clipsToBounds = true
    view.addSubview(previewContainer)

    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    previewContainer.layer.addSublayer(layer)
    self.previewLayer = layer

    quadLayer.fillColor = UIColor(red: 0, green: 0.902, blue: 0.463, alpha: 0.22).cgColor
    quadLayer.strokeColor = UIColor(red: 0, green: 0.902, blue: 0.463, alpha: 1.0).cgColor
    quadLayer.lineWidth = 3.0
    quadLayer.lineJoin = .round
    previewContainer.layer.addSublayer(quadLayer)

    // Top Bar
    topBar.translatesAutoresizingMaskIntoConstraints = false
    topBar.backgroundColor = UIColor.black.withAlphaComponent(0.25)
    view.addSubview(topBar)

    closeButton.translatesAutoresizingMaskIntoConstraints = false
    closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
    closeButton.tintColor = .white
    closeButton.addTarget(self, action: #selector(handleCloseTap), for: .touchUpInside)
    topBar.addSubview(closeButton)

    modeToggleButton.translatesAutoresizingMaskIntoConstraints = false
    modeToggleButton.setTitle(isBatchMode ? "دفعة" : "مفرد", for: .normal)
    modeToggleButton.setTitleColor(.white, for: .normal)
    modeToggleButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 14)
    modeToggleButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
    modeToggleButton.layer.cornerRadius = 18
    modeToggleButton.layer.borderWidth = 1
    modeToggleButton.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
    modeToggleButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)
    modeToggleButton.addTarget(self, action: #selector(handleModeToggle), for: .touchUpInside)
    topBar.addSubview(modeToggleButton)

    torchButton.translatesAutoresizingMaskIntoConstraints = false
    torchButton.setImage(UIImage(systemName: "bolt.slash.fill"), for: .normal)
    torchButton.tintColor = .white
    torchButton.addTarget(self, action: #selector(handleTorchToggle), for: .touchUpInside)
    topBar.addSubview(torchButton)

    // Bottom Bar
    bottomBar.translatesAutoresizingMaskIntoConstraints = false
    bottomBar.backgroundColor = UIColor.black.withAlphaComponent(0.35)
    view.addSubview(bottomBar)

    galleryButton.translatesAutoresizingMaskIntoConstraints = false
    galleryButton.setImage(UIImage(systemName: "photo.on.rectangle"), for: .normal)
    galleryButton.tintColor = .white
    galleryButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
    galleryButton.layer.cornerRadius = 24
    galleryButton.layer.borderWidth = 1
    galleryButton.layer.borderColor = UIColor.white.withAlphaComponent(0.4).cgColor
    galleryButton.addTarget(self, action: #selector(handleGalleryTap), for: .touchUpInside)
    bottomBar.addSubview(galleryButton)

    shutterButton.translatesAutoresizingMaskIntoConstraints = false
    shutterButton.backgroundColor = .white
    shutterButton.layer.cornerRadius = 36
    shutterButton.layer.borderWidth = 4
    shutterButton.layer.borderColor = UIColor(red: 0, green: 0.902, blue: 0.463, alpha: 1.0).cgColor
    shutterButton.addTarget(self, action: #selector(handleShutterTap), for: .touchUpInside)
    bottomBar.addSubview(shutterButton)

    doneButton.translatesAutoresizingMaskIntoConstraints = false
    doneButton.setTitle("تم (0)", for: .normal)
    doneButton.setTitleColor(.black, for: .normal)
    doneButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 15)
    doneButton.backgroundColor = UIColor(red: 0, green: 0.902, blue: 0.463, alpha: 1.0)
    doneButton.layer.cornerRadius = 22
    doneButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
    doneButton.isHidden = true
    doneButton.addTarget(self, action: #selector(handleDoneTap), for: .touchUpInside)
    bottomBar.addSubview(doneButton)

    let safe = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      topBar.topAnchor.constraint(equalTo: safe.topAnchor),
      topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      topBar.heightAnchor.constraint(equalToConstant: 64),

      closeButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
      closeButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
      closeButton.widthAnchor.constraint(equalToConstant: 44),
      closeButton.heightAnchor.constraint(equalToConstant: 44),

      modeToggleButton.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
      modeToggleButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
      modeToggleButton.heightAnchor.constraint(equalToConstant: 36),

      torchButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16),
      torchButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
      torchButton.widthAnchor.constraint(equalToConstant: 44),
      torchButton.heightAnchor.constraint(equalToConstant: 44),

      bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      bottomBar.topAnchor.constraint(equalTo: safe.bottomAnchor, constant: -110),

      galleryButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 24),
      galleryButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
      galleryButton.widthAnchor.constraint(equalToConstant: 48),
      galleryButton.heightAnchor.constraint(equalToConstant: 48),

      shutterButton.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
      shutterButton.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 18),
      shutterButton.widthAnchor.constraint(equalToConstant: 72),
      shutterButton.heightAnchor.constraint(equalToConstant: 72),

      doneButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -24),
      doneButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
      doneButton.heightAnchor.constraint(equalToConstant: 44),
    ])
  }

  private func setupNotifications() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAppDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleSessionWasInterrupted),
      name: .AVCaptureSessionWasInterrupted,
      object: session
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleSessionInterruptionEnded),
      name: .AVCaptureSessionInterruptionEnded,
      object: session
    )
  }

  @objc private func handleAppDidEnterBackground() {
    DocumentDetector.logInfo("App entered background during scanner session")
    if batchItems.isEmpty {
      finishWithResult(nil)
    }
  }

  @objc private func handleSessionWasInterrupted(_ notification: Notification) {
    DocumentDetector.logInfo("AVCaptureSession was interrupted")
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.quadLayer.path = nil
      if self.batchItems.isEmpty {
        self.finishWithResult(nil)
      }
    }
  }

  @objc private func handleSessionInterruptionEnded(_ notification: Notification) {
    DocumentDetector.logInfo("AVCaptureSession interruption ended")
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      if !self.session.isRunning {
        self.session.startRunning()
      }
    }
  }

  private func checkPermissionAndStartSession() {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    switch status {
    case .authorized:
      configureAndStartCamera()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          if granted {
            self?.configureAndStartCamera()
          } else {
            DocumentDetector.logInfo("Camera permission denied by user")
            self?.finishWithResult(nil)
          }
        }
      }
    default:
      DocumentDetector.logInfo("Camera permission status not authorized (\(status.rawValue)), returning nil")
      finishWithResult(nil)
    }
  }

  private func configureAndStartCamera() {
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      self.session.beginConfiguration()
      self.session.sessionPreset = .photo

      guard
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
        let input = try? AVCaptureDeviceInput(device: device),
        self.session.canAddInput(input)
      else {
        self.session.commitConfiguration()
        DispatchQueue.main.async {
          self.finishWithResult(nil)
        }
        return
      }
      self.session.addInput(input)
      self.videoDevice = device

      try? device.lockForConfiguration()
      if device.isFocusModeSupported(.continuousAutoFocus) {
        device.focusMode = .continuousAutoFocus
      }
      if device.isExposureModeSupported(.continuousAutoExposure) {
        device.exposureMode = .continuousAutoExposure
      }
      device.unlockForConfiguration()

      let videoOutput = AVCaptureVideoDataOutput()
      videoOutput.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
      ]
      videoOutput.alwaysDiscardsLateVideoFrames = true
      videoOutput.setSampleBufferDelegate(self, queue: self.videoOutputQueue)
      if self.session.canAddOutput(videoOutput) {
        self.session.addOutput(videoOutput)
      }

      if self.session.canAddOutput(self.photoOutput) {
        self.session.addOutput(self.photoOutput)
        if #available(iOS 13.0, *) {
          self.photoOutput.maxPhotoQualityPrioritization = .speed
        }
      }

      self.session.commitConfiguration()
      self.session.startRunning()
    }
  }

  @objc private func handleModeToggle() {
    isBatchMode.toggle()
    modeToggleButton.setTitle(isBatchMode ? "دفعة" : "مفرد", for: .normal)
    updateDoneButton()
  }

  @objc private func handleTorchToggle() {
    guard let device = videoDevice, device.hasTorch else { return }
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      do {
        try device.lockForConfiguration()
        self.isTorchOn.toggle()
        device.torchMode = self.isTorchOn ? .on : .off
        device.unlockForConfiguration()
        DispatchQueue.main.async {
          let icon = self.isTorchOn ? "bolt.fill" : "bolt.slash.fill"
          self.torchButton.setImage(UIImage(systemName: icon), for: .normal)
          self.torchButton.tintColor = self.isTorchOn ? .systemYellow : .white
        }
      } catch {}
    }
  }

  @objc private func handleCloseTap() {
    if batchItems.isEmpty {
      finishWithResult(nil)
      return
    }
    let alert = UIAlertController(
      title: "صفحات غير محفوظة",
      message: "لديك \(batchItems.count) صفحة ممسوحة. هل تريد حفظها ومتابعة الجلسة أم إلغاء الكل؟",
      preferredStyle: .alert
    )
    alert.addAction(
      UIAlertAction(title: "حفظ ومتابعة", style: .default) { [weak self] _ in
        guard let self = self else { return }
        self.finishWithResult(self.batchItems)
      }
    )
    alert.addAction(
      UIAlertAction(title: "إلغاء الكل", style: .destructive) { [weak self] _ in
        guard let self = self else { return }
        for item in self.batchItems {
          try? FileManager.default.removeItem(atPath: item.path)
        }
        self.batchItems.removeAll()
        self.finishWithResult(nil)
      }
    )
    alert.addAction(UIAlertAction(title: "البقاء في الكاميرا", style: .cancel))
    present(alert, animated: true)
  }

  @objc private func handleDoneTap() {
    guard !batchItems.isEmpty else { return }
    finishWithResult(batchItems)
  }

  @objc private func handleGalleryTap() {
    var config = PHPickerConfiguration()
    config.filter = .images
    config.selectionLimit = isBatchMode ? 0 : 1
    let picker = PHPickerViewController(configuration: config)
    picker.delegate = self
    present(picker, animated: true)
  }

  @objc private func handleShutterTap() {
    let now = CACurrentMediaTime()
    guard !isCapturing, (now - lastShutterTime) >= 0.6 else { return }
    isCapturing = true
    lastShutterTime = now
    shutterTapTimestamp = now
    snappedCornersAtTap = latestQuad

    UIView.animate(
      withDuration: 0.08,
      animations: {
        self.shutterButton.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
      },
      completion: { _ in
        UIView.animate(withDuration: 0.08) {
          self.shutterButton.transform = .identity
        }
      }
    )

    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
      if #available(iOS 13.0, *) {
        settings.photoQualityPrioritization = .speed
      }
      settings.flashMode = .off
      if let conn = self.photoOutput.connection(with: .video) {
        if #available(iOS 17.0, *) {
          if conn.isVideoRotationAngleSupported(90) {
            conn.videoRotationAngle = 90
          }
        } else if conn.isVideoOrientationSupported {
          conn.videoOrientation = .portrait
        }
      }
      self.photoOutput.capturePhoto(with: settings, delegate: self)
    }
  }

  private func updateDoneButton() {
    doneButton.isHidden = !(isBatchMode && !batchItems.isEmpty)
    doneButton.setTitle("تم (\(batchItems.count))", for: .normal)
  }

  private func finishWithResult(_ items: [CapturedScanItem]?) {
    guard !hasFinished else { return }
    hasFinished = true
    let batchFlag = isBatchMode || (items?.count ?? 0) > 1
    let tapTime = shutterTapTimestamp
    dismiss(animated: true) { [onFinish] in
      if tapTime > 0 {
        let totalMs = Int((CACurrentMediaTime() - tapTime) * 1000.0)
        DocumentDetector.logInfo("Capture timing: tap -> reply = \(totalMs)ms")
      }
      onFinish(items, batchFlag)
    }
  }

  private func updateQuadOverlay(_ quad: [CGPoint]?) {
    guard let q = quad, q.count == 4 else {
      quadLayer.path = nil
      return
    }
    let bounds = previewContainer.bounds
    let path = UIBezierPath()
    path.move(to: CGPoint(x: q[0].x * bounds.width, y: q[0].y * bounds.height))
    path.addLine(to: CGPoint(x: q[1].x * bounds.width, y: q[1].y * bounds.height))
    path.addLine(to: CGPoint(x: q[2].x * bounds.width, y: q[2].y * bounds.height))
    path.addLine(to: CGPoint(x: q[3].x * bounds.width, y: q[3].y * bounds.height))
    path.close()
    quadLayer.path = path.cgPath
  }
}

extension ScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
  public func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    frameCounter += 1
    if frameCounter % analyzeEveryNthFrame != 0 { return }
    guard !isAnalyzingFrame, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return
    }
    isAnalyzingFrame = true
    let start = CACurrentMediaTime()
    let detected = DocumentDetector.findQuad(in: pixelBuffer, orientation: .right)
    let elapsedMs = (CACurrentMediaTime() - start) * 1000.0

    analyzerCount += 1
    analyzerTotalMs += elapsedMs
    if analyzerCount >= 30 {
      let avg = analyzerTotalMs / Double(analyzerCount)
      DocumentDetector.logInfo("Live Vision avg frame time (30 frames): \(String(format: "%.1f", avg)) ms (everyNth=\(analyzeEveryNthFrame))")
      if avg > 30.0 && analyzeEveryNthFrame == 1 {
        analyzeEveryNthFrame = 2
        DocumentDetector.logInfo("Analyzer avg > 30ms, switching to analyze every 2nd frame")
      }
      analyzerCount = 0
      analyzerTotalMs = 0
    }

    if let newQuad = detected {
      missedFrameCount = 0
      let smoothed: [CGPoint]
      if let prev = previousQuad, prev.count == 4 {
        let maxJump = (0..<4).map { hypot(newQuad[$0].x - prev[$0].x, newQuad[$0].y - prev[$0].y) }.max() ?? 0
        if maxJump > 0.15 {
          smoothed = newQuad
        } else {
          smoothed = (0..<4).map {
            CGPoint(
              x: prev[$0].x + 0.5 * (newQuad[$0].x - prev[$0].x),
              y: prev[$0].y + 0.5 * (newQuad[$0].y - prev[$0].y)
            )
          }
        }
      } else {
        smoothed = newQuad
      }
      previousQuad = smoothed
      latestQuad = smoothed
      DispatchQueue.main.async { [weak self] in
        self?.updateQuadOverlay(smoothed)
      }
    } else {
      missedFrameCount += 1
      if missedFrameCount >= 5 {
        previousQuad = nil
        latestQuad = nil
        DispatchQueue.main.async { [weak self] in
          self?.updateQuadOverlay(nil)
        }
      }
    }

    isAnalyzingFrame = false
  }
}

extension ScannerViewController: AVCapturePhotoCaptureDelegate {
  public func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    defer {
      DispatchQueue.main.async { [weak self] in
        self?.isCapturing = false
      }
    }
    guard error == nil, let data = photo.fileDataRepresentation() else {
      return
    }

    let dirURL = URL(fileURLWithPath: destinationDir)
    try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
    let fileURL = dirURL.appendingPathComponent("raw_\(UUID().uuidString).jpg")

    do {
      try data.write(to: fileURL, options: .atomic)
    } catch {
      return
    }

    let fileWrittenMs = Int((CACurrentMediaTime() - shutterTapTimestamp) * 1000.0)
    DocumentDetector.logInfo("Capture timing: tap -> fileWritten = \(fileWrittenMs)ms (\(fileURL.lastPathComponent))")

    let dims = DocumentDetector.ensureUprightAndReadDimensions(
      path: fileURL.path,
      isPortraitCameraCapture: true
    ) ?? (width: 1080, height: 1440)
    let quadPoints =
      snappedCornersAtTap
      ?? DocumentDetector.findQuadInFile(path: fileURL.path)
      ?? DocumentDetector.defaultInsetQuad()
    let item = CapturedScanItem(
      path: fileURL.path,
      corners: DocumentDetector.flattenQuad(quadPoints),
      width: dims.width,
      height: dims.height
    )

    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      if self.isBatchMode {
        self.batchItems.append(item)
        self.updateDoneButton()
      } else {
        self.finishWithResult([item])
      }
    }
  }
}

extension ScannerViewController: PHPickerViewControllerDelegate {
  public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard !results.isEmpty else { return }

    let dirURL = URL(fileURLWithPath: destinationDir)
    try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

    let group = DispatchGroup()
    var imported: [CapturedScanItem] = []
    let lock = NSLock()

    for res in results {
      if res.itemProvider.canLoadObject(ofClass: UIImage.self) {
        group.enter()
        res.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
          defer { group.leave() }
          guard let img = object as? UIImage else { return }
          let fileURL = dirURL.appendingPathComponent("raw_\(UUID().uuidString).jpg")
          guard let jpeg = img.jpegData(compressionQuality: 0.95),
            (try? jpeg.write(to: fileURL, options: .atomic)) != nil
          else {
            return
          }
          let dims = DocumentDetector.readUprightDimensions(path: fileURL.path)
            ?? (width: Int(img.size.width), height: Int(img.size.height))
          let quad = DocumentDetector.findQuadInFile(path: fileURL.path)
            ?? DocumentDetector.defaultInsetQuad()
          let item = CapturedScanItem(
            path: fileURL.path,
            corners: DocumentDetector.flattenQuad(quad),
            width: dims.width,
            height: dims.height
          )
          lock.lock()
          imported.append(item)
          lock.unlock()
        }
      }
    }

    group.notify(queue: .main) { [weak self] in
      guard let self = self, !imported.isEmpty else { return }
      if self.isBatchMode {
        self.batchItems.append(contentsOf: imported)
        self.updateDoneButton()
      } else {
        self.finishWithResult(imported)
      }
    }
  }
}
