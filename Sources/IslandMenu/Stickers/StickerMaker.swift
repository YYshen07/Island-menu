import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import VisionKit
import AppKit

/// Turns a picture into a sticker the way Photos and Messages do: the system's subject lifting
/// cuts the foreground out, and a white die-cut border is added round it.
enum StickerMaker {
    enum Failure: LocalizedError {
        case unreadable

        var errorDescription: String? { "无法读取这张图片" }
    }

    private static let maxSide: CGFloat = 640
    /// Border width as a fraction of the sticker's longer side.
    private static let borderFraction: CGFloat = 0.022
    private static let context = CIContext()
    private static let thumbnailSide: CGFloat = 160
    private static let opaqueThreshold: UInt8 = 12

    /// The cut-out subject, trimmed and scaled down; the whole picture when no subject is found.
    /// Uses the same subject lifting as Photos and Messages (VisionKit); effects are applied later
    /// (`styled`), so a sticker's effect can be changed without the original picture.
    @MainActor static func make(from data: Data) async throws -> CGImage {
        if let lifted = await liftNatively(from: data), let image = finish(CIImage(cgImage: lifted)) { return image }
        return try makeWithVision(from: data)
    }

    /// The same without VisionKit, which needs a running app; used from the command line.
    static func makeWithVision(from data: Data) throws -> CGImage {
        guard let picture = CIImage(data: data, options: [.applyOrientationProperty: true]) else { throw Failure.unreadable }
        guard let image = finish((try? liftSubject(from: picture)) ?? picture) else { throw Failure.unreadable }
        return image
    }

    /// What long-pressing a subject in Photos lifts. Nil when the system finds no subject.
    @MainActor private static func liftNatively(from data: Data) async -> CGImage? {
        guard ImageAnalyzer.isSupported, let picture = NSImage(data: data) else { return nil }
        do {
            let analysis = try await ImageAnalyzer().analyze(picture, orientation: .up, configuration: .init([.visualLookUp]))
            let overlay = ImageAnalysisOverlayView()
            overlay.preferredInteractionTypes = .imageSubject
            overlay.analysis = analysis
            let subjects = await overlay.subjects
            guard !subjects.isEmpty else { return nil }
            return try await overlay.image(for: subjects).cgImage(forProposedRect: nil, context: nil, hints: nil)
        } catch {
            return nil
        }
    }

    /// Trims the transparent margin and scales the cut-out to the size stickers are kept at.
    private static func finish(_ subject: CIImage) -> CGImage? {
        guard let full = render(subject) else { return nil }
        let trimmed = CIImage(cgImage: full).cropped(to: opaqueBounds(of: full))
        let scale = min(maxSide / max(trimmed.extent.width, trimmed.extent.height), 1)
        let sized = trimmed.transformed(by: CGAffineTransform(translationX: -trimmed.extent.minX, y: -trimmed.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return render(sized)
    }

    /// Bounding box of the pixels that are not transparent, in Core Image's bottom-left coordinates.
    private static func opaqueBounds(of image: CGImage) -> CGRect {
        let whole = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
              let data = context.data else { return whole }
        context.draw(image, in: whole)
        let alpha = data.bindMemory(to: UInt8.self, capacity: image.width * image.height)
        var minX = image.width, maxX = -1, minY = image.height, maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width where alpha[y * image.width + x] > opaqueThreshold {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return whole }
        // Bitmap rows run top to bottom; Core Image's y runs bottom to top.
        return CGRect(x: minX, y: image.height - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// The cut-out with one of the sticker effects applied.
    static func styled(_ cutout: CGImage, _ style: StickerStyle) -> CGImage {
        let image = CIImage(cgImage: cutout)
        let result: CIImage
        switch style {
        case .original: result = image
        case .outline: result = addBorder(to: image)
        case .comic: result = addBorder(to: comic(image))
        case .puffy: result = addBorder(to: puffy(image))
        case .shiny: result = addBorder(to: shiny(image))
        case .noir: result = addBorder(to: keepShape(of: image, image.applyingFilter("CIPhotoEffectNoir")))
        case .gold: result = addBorder(to: gold(image), color: CIColor(red: 1, green: 0.86, blue: 0.5))
        case .lineArt: result = addBorder(to: lineArt(image))
        case .pixel: result = pixel(image)
        case .neon: result = neon(image)
        }
        return render(result) ?? cutout
    }

    /// A small copy for the effect picker, so ten previews do not cost ten full-size pictures.
    static func thumbnail(of cutout: CGImage) -> CGImage {
        let scale = min(thumbnailSide / CGFloat(max(cutout.width, cutout.height)), 1)
        return render(CIImage(cgImage: cutout).transformed(by: CGAffineTransform(scaleX: scale, y: scale))) ?? cutout
    }

    private static func render(_ image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    private static func liftSubject(from picture: CIImage) throws -> CIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: picture)
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
        let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
        return CIImage(cvPixelBuffer: buffer)
    }

    /// White outline: the sticker's own alpha, grown outwards and filled white, under the sticker.
    private static func addBorder(to sticker: CIImage, color: CIColor = .white, glow: CGFloat = 0) -> CIImage {
        let width = max(sticker.extent.width, sticker.extent.height) * borderFraction
        let margin = width * (2 + glow * 2)
        let padded = sticker.transformed(by: CGAffineTransform(translationX: margin - sticker.extent.minX, y: margin - sticker.extent.minY))
        let canvas = CGRect(x: 0, y: 0, width: padded.extent.maxX + margin, height: padded.extent.maxY + margin)
        let white = CIFilter.colorMatrix()
        white.inputImage = padded
        white.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        white.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        white.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        white.biasVector = CIVector(x: color.red, y: color.green, z: color.blue, w: 0)
        let grown = CIFilter.morphologyMaximum()
        grown.inputImage = white.outputImage?.premultiplyingAlpha()
        grown.radius = Float(width)
        guard let outline = grown.outputImage else { return padded }
        let halo = glow > 0 ? outline.applyingGaussianBlur(sigma: width * glow).composited(over: outline.applyingGaussianBlur(sigma: width * glow * 0.4)) : nil
        return padded.composited(over: halo.map { outline.composited(over: $0) } ?? outline).cropped(to: canvas)
    }

    /// Inked outlines and flat halftone colour.
    private static func comic(_ image: CIImage) -> CIImage {
        let filter = CIFilter.comicEffect()
        filter.inputImage = image
        return keepShape(of: image, filter.outputImage)
    }

    /// Looks inflated: light catches the upper-left rim and the lower-right rim falls into shade.
    private static func puffy(_ image: CIImage) -> CIImage {
        let depth = max(image.extent.width, image.extent.height) * 0.02
        let lit = rim(of: image, depth: depth, towards: CGPoint(x: 1, y: -1))
        let shaded = rim(of: image, depth: depth, towards: CGPoint(x: -1, y: 1))
        let highlight = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.5)).cropped(to: image.extent)
        let shadow = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.4)).cropped(to: image.extent)
        let withShadow = shadow.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: shaded])
        return keepShape(of: image, highlight.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: withShadow, kCIInputMaskImageKey: lit]))
    }

    /// Greyscale mask that is bright along the rim facing away from `towards`: the shape's own
    /// coverage with a blurred copy, pushed in that direction, taken out of it.
    private static func rim(of image: CIImage, depth: CGFloat, towards: CGPoint) -> CIImage {
        let coverage = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).composited(over: CIImage(color: .black).cropped(to: image.extent))
        let pushed = coverage.clampedToExtent().applyingGaussianBlur(sigma: depth)
            .transformed(by: CGAffineTransform(translationX: towards.x * depth, y: towards.y * depth)).cropped(to: image.extent)
        return coverage.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: pushed.applyingFilter("CIColorInvert")])
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": 1.8])
    }

    /// Holographic foil: a diagonal rainbow laid over the picture.
    private static func shiny(_ image: CIImage) -> CIImage {
        let extent = image.extent
        let hues: [CIColor] = [CIColor(red: 1, green: 0.35, blue: 0.6), CIColor(red: 1, green: 0.85, blue: 0.3), CIColor(red: 0.35, green: 1, blue: 0.7),
                               CIColor(red: 0.35, green: 0.7, blue: 1), CIColor(red: 0.8, green: 0.45, blue: 1)]
        var foil = CIImage(color: hues[0]).cropped(to: extent)
        let step = (extent.width + extent.height) / CGFloat(hues.count - 1)
        for index in 1..<hues.count {
            let gradient = CIFilter.linearGradient()
            let from = CGFloat(index - 1) * step, to = CGFloat(index) * step
            gradient.point0 = CGPoint(x: extent.minX + from / 2, y: extent.minY + from / 2)
            gradient.point1 = CGPoint(x: extent.minX + to / 2, y: extent.minY + to / 2)
            gradient.color0 = CIColor(red: hues[index].red, green: hues[index].green, blue: hues[index].blue, alpha: 0)
            gradient.color1 = hues[index]
            foil = (gradient.outputImage ?? foil).cropped(to: extent).composited(over: foil)
        }
        let sheen = foil.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.55)])
        return keepShape(of: image, sheen.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.25, kCIInputBrightnessKey: 0.04]))
    }

    /// Filters can spill outside the cut-out or fill its transparent parts; this restores its outline.
    private static func keepShape(of original: CIImage, _ filtered: CIImage?) -> CIImage {
        guard let filtered else { return original }
        return filtered.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: original]).cropped(to: original.extent)
    }

    /// Gold foil: the picture's tones mapped from deep bronze to bright gold.
    private static func gold(_ image: CIImage) -> CIImage {
        let toned = image.applyingFilter("CIFalseColor", parameters: ["inputColor0": CIColor(red: 0.22, green: 0.12, blue: 0.02), "inputColor1": CIColor(red: 1, green: 0.9, blue: 0.55)])
            .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.25])
        return keepShape(of: image, toned)
    }

    /// Pencil drawing: the picture's edges in dark lines on a white sticker.
    private static func lineArt(_ image: CIImage) -> CIImage {
        let paper = CIImage(color: .white).cropped(to: image.extent)
        let lines = image.composited(over: paper).applyingFilter("CILineOverlay", parameters: ["inputEdgeIntensity": 1.4, "inputThreshold": 0.08, "inputContrast": 60])
        return keepShape(of: image, lines.composited(over: paper))
    }

    /// Chunky pixels, edges included.
    private static func pixel(_ image: CIImage) -> CIImage {
        let block = max(image.extent.width, image.extent.height) / 30
        return image.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: block, kCIInputCenterKey: CIVector(x: image.extent.minX, y: image.extent.minY)]).cropped(to: image.extent)
    }

    /// A glowing tube round a more saturated picture.
    private static func neon(_ image: CIImage) -> CIImage {
        let vivid = keepShape(of: image, image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.5, kCIInputContrastKey: 1.1]))
        return addBorder(to: vivid, color: CIColor(red: 0.2, green: 1, blue: 0.9), glow: 2.5)
    }
}
