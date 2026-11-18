import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Captures images of standalone menu bar item windows (macOS 14–26).
///
/// On macOS 27 (`MenuBarAgent`), individual status items no longer have
/// standalone windows and may be folded inside the native `«` overflow tray,
/// so the tray displays each item's native application icon instead of cropping
/// the shared menu bar surface.
enum MenuBarItemCapturer {
    struct Capture: @unchecked Sendable {
        let image: CGImage
    }

    struct Analysis: Equatable {
        let isBlank: Bool
        let isMonochrome: Bool
    }

    static var isScreenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func capture(
        windows: [CGWindowID: CGRect],
        scale: CGFloat
    ) async -> [CGWindowID: Capture] {
        guard #available(macOS 14.0, *), !windows.isEmpty, isScreenRecordingGranted else {
            return [:]
        }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        ) else { return [:] }

        var result: [CGWindowID: Capture] = [:]
        for scWindow in content.windows {
            guard let frame = windows[scWindow.windowID],
                  frame.width > 1, frame.height > 1 else { continue }
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int((frame.width * scale).rounded()))
            configuration.height = max(1, Int((frame.height * scale).rounded()))
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.captureResolution = .best
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            guard let image = try? await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            ) else { continue }
            guard !analyze(image).isBlank else { continue }
            result[scWindow.windowID] = Capture(image: image)
        }
        return result
    }

    static func analyze(_ image: CGImage) -> Analysis {
        guard image.width > 0, image.height > 0 else {
            return Analysis(isBlank: true, isMonochrome: false)
        }
        let width = max(1, min(image.width, 48))
        let height = max(1, min(image.height, 32))
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return Analysis(isBlank: true, isMonochrome: false) }

        var visible = 0
        var colored = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            guard alpha > 40 else { continue }
            visible += 1
            let r = Int(pixels[index]) * 255 / alpha
            let g = Int(pixels[index + 1]) * 255 / alpha
            let b = Int(pixels[index + 2]) * 255 / alpha
            if max(r, g, b) - min(r, g, b) > 40 {
                colored += 1
            }
        }
        return Analysis(
            isBlank: visible < 3,
            isMonochrome: colored * 20 <= visible
        )
    }
}
