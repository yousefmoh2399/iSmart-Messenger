import UIKit
import AVFoundation
import QuartzCore
#if canImport(Lottie)
import Lottie
#endif

struct EasySplashNativeConfig {
    let duration: TimeInterval
    let themeMode: String
    let text: String?
    let backgroundLightHex: String
    let backgroundDarkHex: String
    let imageLightName: String?
    let imageDarkName: String?
    let lottieLightName: String?
    let lottieDarkName: String?
    let indicatorLottieLightName: String?
    let indicatorLottieDarkName: String?
    let soundName: String?
    let textColorLightHex: String
    let textColorDarkHex: String
    let indicatorColorLightHex: String
    let indicatorColorDarkHex: String
    let showsIndicator: Bool
    let indicatorStyle: String
    let indicatorPosition: String
    let textPosition: String
    let indicatorOffsetY: CGFloat
    let textOffsetY: CGFloat
    let visualOffsetY: CGFloat
    let visualWidth: CGFloat
    let visualHeight: CGFloat
    let indicatorWidth: CGFloat
    let indicatorHeight: CGFloat
    let textSize: CGFloat
    let flutterImageAssetLight: String?
    let flutterImageAssetDark: String?
    let flutterLottieAssetLight: String?
    let flutterLottieAssetDark: String?
    let flutterIndicatorLottieAssetLight: String?
    let flutterIndicatorLottieAssetDark: String?
    let flutterSoundAsset: String?
}

enum IndicatorPlacement: String {
    case auto
    case belowVisual = "below_visual"
    case aboveText = "above_text"
    case top
    case center
    case bottom
}

enum TextPlacement: String {
    case auto
    case belowVisual = "below_visual"
    case top
    case center
    case bottom
}

enum IndicatorVisualStyle: String {
    case circular
    case linear
    case dots
    case pulse
    case wave
    case bounce
    case orbit
    case lottie
}

final class EasySplashCoordinator {
    private weak var providedWindow: UIWindow?
    private let config: EasySplashNativeConfig
    private var overlayWindow: UIWindow?
    private var presentationAttempts = 0

    init(window: UIWindow?, config: EasySplashNativeConfig) {
        self.providedWindow = window
        self.config = config
    }

    func presentIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            self?.presentWhenWindowIsReady()
        }
    }

    private func presentWhenWindowIsReady() {
        guard overlayWindow == nil else { return }
        guard let baseWindow = resolvedBaseWindow() else {
            presentationAttempts += 1
            if presentationAttempts <= 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.presentWhenWindowIsReady()
                }
            }
            return
        }

        let overlay = UIWindow(frame: baseWindow.bounds)
        if #available(iOS 13.0, *) {
            overlay.windowScene = baseWindow.windowScene ?? EasySplashCoordinator.activeWindowScene()
        }
        overlay.accessibilityIdentifier = "EasySplashOverlay"
        overlay.windowLevel = baseWindow.windowLevel + 1
        let controller = SplashViewController(config: config) { [weak self] in
            self?.dismiss()
        }
        overlay.rootViewController = controller
        overlay.isHidden = false
        overlayWindow = overlay
    }

    private func resolvedBaseWindow() -> UIWindow? {
        if let providedWindow = providedWindow {
            return providedWindow
        }
        if #available(iOS 13.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
                ?? UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }
                    .first
        }
        return UIApplication.shared.keyWindow
    }

    @available(iOS 13.0, *)
    private static func activeWindowScene() -> UIWindowScene? {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
    }

    private func dismiss() {
        overlayWindow?.isHidden = true
        overlayWindow = nil
    }
}

final class SplashViewController: UIViewController {
    private let config: EasySplashNativeConfig
    private let completion: () -> Void
    private var player: AVAudioPlayer?

    init(config: EasySplashNativeConfig, completion: @escaping () -> Void) {
        self.config = config
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = SplashViewController.dynamicColor(
            lightHex: config.backgroundLightHex,
            darkHex: config.backgroundDarkHex,
            mode: config.themeMode
        )
        setupContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleCompletion()
        playSoundIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopAnimations(in: view)
        player?.stop()
    }

    private func setupContent() {
        let safeArea = view.safeAreaLayoutGuide

        var visualView: UIView?

#if canImport(Lottie)
        if let lottieName = resolvedLottieName() {
            var animation: LottieAnimation? = LottieAnimation.named(lottieName, bundle: .main)
            if animation == nil,
               let fallback = resolvedLottieFallback(),
               let url = SplashViewController.fileURL(named: lottieName, fallback: fallback) {
                animation = try? LottieAnimation.filepath(url.path)
            }
            if let animation = animation {
                let animationView = LottieAnimationView(animation: animation)
                animationView.translatesAutoresizingMaskIntoConstraints = false
                animationView.loopMode = LottieLoopMode.loop
                animationView.contentMode = UIView.ContentMode.scaleAspectFit
                animationView.play()
                view.addSubview(animationView)
                visualView = animationView
            }
        }
#endif

        if visualView == nil,
           let imageName = resolvedImageName(),
           let image = SplashViewController.loadImage(named: imageName, fallback: resolvedImageFallback()) {
            let imageView = UIImageView(image: image)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = UIView.ContentMode.scaleAspectFit
            view.addSubview(imageView)
            visualView = imageView
        }

        let hasText = (config.text?.isEmpty == false)
        let indicatorPlacementRaw = IndicatorPlacement(rawValue: config.indicatorPosition) ?? .auto
        let textPlacementRaw = TextPlacement(rawValue: config.textPosition) ?? .auto

        let resolvedTextPlacement: TextPlacement = {
            switch textPlacementRaw {
            case .auto:
                return visualView != nil ? .belowVisual : .bottom
            default:
                return textPlacementRaw
            }
        }()

        let resolvedIndicatorPlacement: IndicatorPlacement = {
            switch indicatorPlacementRaw {
            case .auto:
                if visualView != nil { return .belowVisual }
                return hasText ? .aboveText : .belowVisual
            case .aboveText:
                return hasText ? .aboveText : .belowVisual
            case .belowVisual:
                return .belowVisual
            case .top, .center, .bottom:
                return indicatorPlacementRaw
            }
        }()

        var label: UILabel?
        if hasText, let text = config.text {
            let textLabel = UILabel()
            textLabel.translatesAutoresizingMaskIntoConstraints = false
            textLabel.text = text
            textLabel.textColor = SplashViewController.dynamicColor(
                lightHex: config.textColorLightHex,
                darkHex: config.textColorDarkHex,
                mode: config.themeMode
            )
            textLabel.font = UIFont.systemFont(ofSize: config.textSize, weight: .medium)
            textLabel.numberOfLines = 0
            textLabel.textAlignment = .center
            view.addSubview(textLabel)
            label = textLabel
        }

        var indicatorView: UIView?
        if config.showsIndicator {
            let indicatorColor = SplashViewController.dynamicColor(
                lightHex: config.indicatorColorLightHex,
                darkHex: config.indicatorColorDarkHex,
                mode: config.themeMode
            )
            let style = IndicatorVisualStyle(rawValue: config.indicatorStyle) ?? .circular

            switch style {
            case .linear:
                let progress = UIProgressView(progressViewStyle: .bar)
                progress.translatesAutoresizingMaskIntoConstraints = false
                progress.progressTintColor = indicatorColor
                progress.trackTintColor = indicatorColor.withAlphaComponent(0.22)
                progress.progress = 0.35
                UIView.animate(withDuration: 0.9, delay: 0, options: [.repeat, .autoreverse, .curveEaseInOut]) {
                    progress.setProgress(1.0, animated: true)
                }
                view.addSubview(progress)
                indicatorView = progress
            case .dots:
                let stack = UIStackView()
                stack.translatesAutoresizingMaskIntoConstraints = false
                stack.tag = 230013
                stack.axis = .horizontal
                stack.alignment = .center
                stack.distribution = .equalSpacing
                stack.spacing = 0
                let dotSize = max(2, min(10, min((config.indicatorWidth > 0 ? config.indicatorWidth : 72) / 5, (config.indicatorHeight > 0 ? config.indicatorHeight : 18) * 0.72)))
                for index in 0..<3 {
                    let dot = UIView()
                    dot.translatesAutoresizingMaskIntoConstraints = false
                    dot.backgroundColor = indicatorColor
                    dot.layer.cornerRadius = dotSize / 2
                    dot.alpha = 0.35
                    NSLayoutConstraint.activate([
                        dot.widthAnchor.constraint(equalToConstant: dotSize),
                        dot.heightAnchor.constraint(equalToConstant: dotSize)
                    ])
                    stack.addArrangedSubview(dot)
                    dot.layer.shouldRasterize = true
                    dot.layer.rasterizationScale = UIScreen.main.scale
                    addKeyframeAnimation(dot.layer, keyPath: "opacity", values: [0.35, 1, 0.35], duration: 0.9, delay: Double(index) * 0.15, key: "simpleSplashDotsOpacity")
                    addKeyframeAnimation(dot.layer, keyPath: "transform.translation.y", values: [0, -dotSize * 0.5, 0], duration: 0.9, delay: Double(index) * 0.15, key: "simpleSplashDotsLift")
                }
                view.addSubview(stack)
                indicatorView = stack
            case .pulse:
                let pulse = UIView()
                pulse.translatesAutoresizingMaskIntoConstraints = false
                pulse.tag = 230011
                pulse.backgroundColor = indicatorColor
                pulse.layer.cornerRadius = 18
                pulse.alpha = 0.75
                pulse.layer.shouldRasterize = true
                pulse.layer.rasterizationScale = UIScreen.main.scale
                addKeyframeAnimation(pulse.layer, keyPath: "transform.scale", values: [0.75, 1.15, 0.75], duration: 1.0, key: "simpleSplashPulseScale")
                addKeyframeAnimation(pulse.layer, keyPath: "opacity", values: [0.55, 1, 0.55], duration: 1.0, key: "simpleSplashPulseOpacity")
                view.addSubview(pulse)
                indicatorView = pulse
            case .wave:
                let stack = UIStackView()
                stack.translatesAutoresizingMaskIntoConstraints = false
                stack.tag = 230014
                stack.axis = .horizontal
                stack.alignment = .center
                stack.distribution = .equalSpacing
                stack.spacing = 0
                let barWidth = max(2, min(8, (config.indicatorWidth > 0 ? config.indicatorWidth : 72) / 7))
                let barHeight = config.indicatorHeight > 0 ? config.indicatorHeight : 36
                for index in 0..<3 {
                    let bar = UIView()
                    bar.translatesAutoresizingMaskIntoConstraints = false
                    bar.backgroundColor = indicatorColor
                    bar.layer.cornerRadius = barWidth / 2
                    bar.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                    NSLayoutConstraint.activate([
                        bar.widthAnchor.constraint(equalToConstant: barWidth),
                        bar.heightAnchor.constraint(equalToConstant: barHeight)
                    ])
                    stack.addArrangedSubview(bar)
                    bar.layer.shouldRasterize = true
                    bar.layer.rasterizationScale = UIScreen.main.scale
                    addKeyframeAnimation(bar.layer, keyPath: "transform.scale.y", values: [1, 0.35, 1], duration: 0.8, delay: Double(index) * 0.12, key: "simpleSplashWaveScale")
                }
                view.addSubview(stack)
                indicatorView = stack
            case .bounce:
                let stack = UIStackView()
                stack.translatesAutoresizingMaskIntoConstraints = false
                stack.tag = 230015
                stack.axis = .horizontal
                stack.alignment = .center
                stack.distribution = .equalSpacing
                stack.spacing = 0
                let dotSize = max(2, min(10, min((config.indicatorWidth > 0 ? config.indicatorWidth : 72) / 5, (config.indicatorHeight > 0 ? config.indicatorHeight : 28) * 0.72)))
                for index in 0..<3 {
                    let dot = UIView()
                    dot.translatesAutoresizingMaskIntoConstraints = false
                    dot.backgroundColor = indicatorColor
                    dot.layer.cornerRadius = dotSize / 2
                    NSLayoutConstraint.activate([
                        dot.widthAnchor.constraint(equalToConstant: dotSize),
                        dot.heightAnchor.constraint(equalToConstant: dotSize)
                    ])
                    stack.addArrangedSubview(dot)
                    dot.layer.shouldRasterize = true
                    dot.layer.rasterizationScale = UIScreen.main.scale
                    addKeyframeAnimation(dot.layer, keyPath: "transform.translation.y", values: [0, -dotSize, 0], duration: 0.76, delay: Double(index) * 0.12, key: "simpleSplashBounce")
                }
                view.addSubview(stack)
                indicatorView = stack
            case .orbit:
                let container = UIView()
                container.translatesAutoresizingMaskIntoConstraints = false
                container.tag = 230016
                let size = config.indicatorWidth > 0 ? config.indicatorWidth : (config.indicatorHeight > 0 ? config.indicatorHeight : 44)
                let dotSize = max(2, min(14, size / 4))
                for index in 0..<2 {
                    let dot = UIView()
                    dot.translatesAutoresizingMaskIntoConstraints = false
                    dot.backgroundColor = indicatorColor
                    dot.alpha = index == 0 ? 1 : 0.45
                    dot.layer.cornerRadius = dotSize / 2
                    container.addSubview(dot)
                    NSLayoutConstraint.activate([
                        dot.widthAnchor.constraint(equalToConstant: dotSize),
                        dot.heightAnchor.constraint(equalToConstant: dotSize),
                        dot.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                        index == 0
                            ? dot.topAnchor.constraint(equalTo: container.topAnchor)
                            : dot.bottomAnchor.constraint(equalTo: container.bottomAnchor)
                    ])
                }
                container.layer.shouldRasterize = true
                container.layer.rasterizationScale = UIScreen.main.scale
                addRotationAnimation(container.layer, duration: 1.1, key: "simpleSplashOrbit")
                view.addSubview(container)
                indicatorView = container
            case .lottie:
#if canImport(Lottie)
                if let lottieName = resolvedIndicatorLottieName() {
                    var animation: LottieAnimation? = LottieAnimation.named(lottieName, bundle: .main)
                    if animation == nil,
                       let fallback = resolvedIndicatorLottieFallback(),
                       let url = SplashViewController.fileURL(named: lottieName, fallback: fallback) {
                        animation = try? LottieAnimation.filepath(url.path)
                    }
                    if let animation = animation {
                        let animationView = LottieAnimationView(animation: animation)
                        animationView.translatesAutoresizingMaskIntoConstraints = false
                        animationView.tag = 230012
                        animationView.loopMode = LottieLoopMode.loop
                        animationView.contentMode = UIView.ContentMode.scaleAspectFit
                        animationView.play()
                        view.addSubview(animationView)
                        indicatorView = animationView
                    }
                }
#endif
                if indicatorView == nil {
                    let indicator = UIActivityIndicatorView(style: .medium)
                    indicator.translatesAutoresizingMaskIntoConstraints = false
                    indicator.hidesWhenStopped = false
                    indicator.color = indicatorColor
                    indicator.startAnimating()
                    view.addSubview(indicator)
                    indicatorView = indicator
                }
            case .circular:
                let indicator = UIActivityIndicatorView(style: .medium)
                indicator.translatesAutoresizingMaskIntoConstraints = false
                indicator.hidesWhenStopped = false
                indicator.color = indicatorColor
                indicator.startAnimating()
                view.addSubview(indicator)
                indicatorView = indicator
            }
        }

        var effectiveIndicatorPlacement = resolvedIndicatorPlacement
        if indicatorView == nil {
            effectiveIndicatorPlacement = .belowVisual
        } else if label == nil && resolvedIndicatorPlacement == .aboveText {
            effectiveIndicatorPlacement = .belowVisual
        }

        var effectiveTextPlacement = resolvedTextPlacement
        if effectiveTextPlacement == .belowVisual,
           visualView == nil,
           effectiveIndicatorPlacement != .belowVisual {
            effectiveTextPlacement = .bottom
        }

        let indicatorUsesAbsolutePlacement = effectiveIndicatorPlacement == .top || effectiveIndicatorPlacement == .center || effectiveIndicatorPlacement == .bottom
        let textUsesAbsolutePlacement = effectiveTextPlacement == .top || effectiveTextPlacement == .center || effectiveTextPlacement == .bottom

        var constraints: [NSLayoutConstraint] = []

        if let visual = visualView {
            constraints.append(visual.centerXAnchor.constraint(equalTo: view.centerXAnchor))
            constraints.append(visual.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: config.visualOffsetY))
            constraints.append(visual.widthAnchor.constraint(equalToConstant: config.visualWidth))
            constraints.append(visual.heightAnchor.constraint(equalToConstant: config.visualHeight))
        }

        if let indicator = indicatorView {
            constraints.append(indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor))
            if indicator is UIProgressView {
                constraints.append(indicator.widthAnchor.constraint(equalToConstant: config.indicatorWidth > 0 ? config.indicatorWidth : 160))
                constraints.append(indicator.heightAnchor.constraint(equalToConstant: config.indicatorHeight > 0 ? config.indicatorHeight : 6))
            } else if indicator is UIStackView {
                constraints.append(indicator.widthAnchor.constraint(equalToConstant: config.indicatorWidth > 0 ? config.indicatorWidth : 72))
                if indicator.tag == 230014 {
                    constraints.append(indicator.heightAnchor.constraint(equalToConstant: config.indicatorHeight > 0 ? config.indicatorHeight : 36))
                } else if indicator.tag == 230015 {
                    constraints.append(indicator.heightAnchor.constraint(equalToConstant: config.indicatorHeight > 0 ? config.indicatorHeight : 28))
                } else {
                    constraints.append(indicator.heightAnchor.constraint(equalToConstant: config.indicatorHeight > 0 ? config.indicatorHeight : 18))
                }
            } else if indicator.tag == 230012 {
                constraints.append(indicator.widthAnchor.constraint(equalToConstant: config.indicatorWidth > 0 ? config.indicatorWidth : 72))
                constraints.append(indicator.heightAnchor.constraint(equalToConstant: config.indicatorHeight > 0 ? config.indicatorHeight : 72))
            } else if indicator.tag == 230011 {
                constraints.append(indicator.widthAnchor.constraint(equalToConstant: config.indicatorWidth > 0 ? config.indicatorWidth : 36))
                constraints.append(indicator.heightAnchor.constraint(equalToConstant: config.indicatorHeight > 0 ? config.indicatorHeight : 36))
            } else if indicator.tag == 230016 {
                let size = config.indicatorWidth > 0 ? config.indicatorWidth : (config.indicatorHeight > 0 ? config.indicatorHeight : 44)
                constraints.append(indicator.widthAnchor.constraint(equalToConstant: size))
                constraints.append(indicator.heightAnchor.constraint(equalToConstant: size))
            } else {
                constraints.append(indicator.widthAnchor.constraint(equalToConstant: config.indicatorWidth > 0 ? config.indicatorWidth : 36))
                constraints.append(indicator.heightAnchor.constraint(equalToConstant: config.indicatorHeight > 0 ? config.indicatorHeight : 36))
            }
        }

        if let label = label {
            constraints.append(label.centerXAnchor.constraint(equalTo: view.centerXAnchor))
        }

        var previousAnchor: NSLayoutYAxisAnchor = visualView?.bottomAnchor ?? safeArea.topAnchor
        var isFirstItem = true
        var chain: [UIView] = []

        if let indicator = indicatorView,
           !indicatorUsesAbsolutePlacement,
           effectiveIndicatorPlacement != .aboveText {
            chain.append(indicator)
        }

        if let label = label, effectiveTextPlacement == .belowVisual, !textUsesAbsolutePlacement {
            chain.append(label)
        }

        for view in chain {
            let spacing: CGFloat = isFirstItem ? 24 : 16
            constraints.append(view.topAnchor.constraint(equalTo: previousAnchor, constant: spacing))
            previousAnchor = view.bottomAnchor
            isFirstItem = false
        }

        if let indicator = indicatorView,
           chain.first === indicator,
           visualView == nil,
           label == nil {
            constraints.append(indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor))
        }

        if let label = label {
            switch effectiveTextPlacement {
            case .top:
                constraints.append(label.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 64 + config.textOffsetY))
            case .center:
                constraints.append(label.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: config.textOffsetY))
            case .bottom:
                constraints.append(label.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -32 + config.textOffsetY))
                if let indicator = indicatorView, !indicatorUsesAbsolutePlacement {
                    if effectiveIndicatorPlacement == .aboveText {
                        constraints.append(indicator.bottomAnchor.constraint(equalTo: label.topAnchor, constant: -16))
                    } else {
                        constraints.append(indicator.bottomAnchor.constraint(lessThanOrEqualTo: label.topAnchor, constant: -16))
                    }
                } else if let visual = visualView {
                    constraints.append(label.topAnchor.constraint(greaterThanOrEqualTo: visual.bottomAnchor, constant: 24))
                }
            case .belowVisual:
                constraints.append(label.bottomAnchor.constraint(lessThanOrEqualTo: safeArea.bottomAnchor, constant: -24))
                if visualView == nil && indicatorView == nil {
                    constraints.append(label.centerYAnchor.constraint(equalTo: view.centerYAnchor))
                }
            case .auto:
                break
            }
        }

        if let indicator = indicatorView {
            switch effectiveIndicatorPlacement {
            case .top:
                constraints.append(indicator.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 64 + config.indicatorOffsetY))
            case .center:
                constraints.append(indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: config.indicatorOffsetY))
            case .bottom:
                constraints.append(indicator.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -80 + config.indicatorOffsetY))
            case .auto, .belowVisual, .aboveText:
                break
            }
        }

        if let indicator = indicatorView,
           label == nil,
           visualView == nil,
           effectiveIndicatorPlacement == .belowVisual {
            constraints.append(indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor))
        }

        if let indicator = indicatorView,
           let label = label,
           effectiveIndicatorPlacement == .aboveText {
            constraints.append(indicator.bottomAnchor.constraint(equalTo: label.topAnchor, constant: -16))
        }

        NSLayoutConstraint.activate(constraints)
    }

    private func resolvedImageName() -> String? {
        if isDarkModeActive() {
            return config.imageDarkName ?? config.imageLightName
        }
        return config.imageLightName ?? config.imageDarkName
    }

    private func resolvedImageFallback() -> String? {
        if isDarkModeActive() {
            return config.flutterImageAssetDark ?? config.flutterImageAssetLight ?? config.flutterImageAssetDark
        }
        return config.flutterImageAssetLight ?? config.flutterImageAssetDark
    }

    private func resolvedLottieName() -> String? {
        if isDarkModeActive() {
            return config.lottieDarkName ?? config.lottieLightName
        }
        return config.lottieLightName ?? config.lottieDarkName
    }

    private func resolvedLottieFallback() -> String? {
        if isDarkModeActive() {
            return config.flutterLottieAssetDark ?? config.flutterLottieAssetLight ?? config.flutterLottieAssetDark
        }
        return config.flutterLottieAssetLight ?? config.flutterLottieAssetDark
    }

    private func resolvedIndicatorLottieName() -> String? {
        if isDarkModeActive() {
            return config.indicatorLottieDarkName ?? config.indicatorLottieLightName
        }
        return config.indicatorLottieLightName ?? config.indicatorLottieDarkName
    }

    private func resolvedIndicatorLottieFallback() -> String? {
        if isDarkModeActive() {
            return config.flutterIndicatorLottieAssetDark ?? config.flutterIndicatorLottieAssetLight ?? config.flutterIndicatorLottieAssetDark
        }
        return config.flutterIndicatorLottieAssetLight ?? config.flutterIndicatorLottieAssetDark
    }

    private func addKeyframeAnimation(
        _ layer: CALayer,
        keyPath: String,
        values: [Any],
        duration: CFTimeInterval,
        delay: CFTimeInterval = 0,
        key: String
    ) {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.duration = duration
        animation.beginTime = CACurrentMediaTime() + delay
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = true
        layer.add(animation, forKey: key)
    }

    private func addRotationAnimation(
        _ layer: CALayer,
        duration: CFTimeInterval,
        key: String
    ) {
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = Double.pi * 2
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = true
        layer.add(animation, forKey: key)
    }

    private func stopAnimations(in root: UIView) {
        root.layer.removeAllAnimations()
        for subview in root.subviews {
            stopAnimations(in: subview)
        }
    }

    private func isDarkModeActive() -> Bool {
        switch config.themeMode {
        case "dark":
            return true
        case "light":
            return false
        default:
            if #available(iOS 13.0, *) {
                return traitCollection.userInterfaceStyle == .dark
            }
            return false
        }
    }

    private func scheduleCompletion() {
        DispatchQueue.main.asyncAfter(deadline: .now() + config.duration) { [weak self] in
            self?.completion()
        }
    }

    private func playSoundIfNeeded() {
        guard let soundName = config.soundName,
              let url = SplashViewController.fileURL(named: soundName, fallback: config.flutterSoundAsset) else { return }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            print("EasySplash: could not play sound (soundName): \(error)")
        }
    }

    private static func dynamicColor(lightHex: String, darkHex: String, mode: String) -> UIColor {
        let light = color(from: lightHex)
        let dark = color(from: darkHex)
        if mode == "dark" {
            return dark
        }
        if mode == "light" {
            return light
        }
        if #available(iOS 13.0, *) {
            return UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        }
        return light
    }

    private static func color(from hex: String) -> UIColor {
        var normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("#") {
            normalized.removeFirst()
        }
        guard normalized.count == 6,
              let value = UInt32(normalized, radix: 16) else {
            return .white
        }
        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0
        return UIColor(red: red, green: green, blue: blue, alpha: 1.0)
    }

    private static func loadImage(named name: String, fallback: String?) -> UIImage? {
        guard let url = fileURL(named: name, fallback: fallback) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private static func textColor(from hex: String?) -> UIColor {
        if let hex = hex {
            return color(from: hex)
        }
        if #available(iOS 13.0, *) {
            return UIColor.label
        }
        return UIColor.white
    }

    private static func fileURL(named name: String, fallback: String?) -> URL? {
        if let direct = bundledURL(for: name) {
            return direct
        }
        if let fallback = fallback,
           let fallbackURL = flutterAssetURL(for: fallback) {
            return fallbackURL
        }
        return nil
    }

    private static func bundledURL(for name: String) -> URL? {
        let components = name.split(separator: ".")
        let bundles = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        for bundle in bundles {
            if components.count > 1 {
                let file = components.dropLast().joined(separator: ".")
                let ext = String(components.last!)
                if let path = bundle.path(forResource: file, ofType: ext) {
                    return URL(fileURLWithPath: path)
                }
            }
            if let path = bundle.path(forResource: name, ofType: nil) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private static func flutterAssetURL(for assetPath: String) -> URL? {
        let normalized = assetPath.hasPrefix("/") ? String(assetPath.dropFirst()) : assetPath
        let candidates = [
            "flutter_assets/(normalized)",
            "Frameworks/App.framework/flutter_assets/(normalized)",
            "App.framework/flutter_assets/(normalized)"
        ]

        let roots = ([Bundle.main] + Bundle.allBundles + Bundle.allFrameworks)
            .compactMap { $0.resourceURL }

        for root in roots {
            for candidate in candidates {
                let url = root.appendingPathComponent(candidate)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }

        if let privateFrameworksURL = Bundle.main.privateFrameworksURL {
            let url = privateFrameworksURL
                .appendingPathComponent("App.framework")
                .appendingPathComponent("flutter_assets")
                .appendingPathComponent(normalized)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }
}
