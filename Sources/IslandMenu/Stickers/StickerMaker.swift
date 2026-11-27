import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

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

    /// The cut-out subject, scaled down; the whole picture when no subject is found. Effects are
    /// applied later (`styled`), so a sticker's effect can be changed without the original picture.
    static func make(from data: Data) throws -> CGImage {
        guard let picture = CIImage(data: data, options: [.applyOrientationProperty: true]) else { throw Failure.unreadable }
        let subject = (try? liftSubject(from: picture)) ?? picture
        let scale = min(maxSide / max(subject.extent.width, subject.extent.height), 1)
        let sized = subject.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let image = render(sized) else { throw Failure.unreadable }
        return image
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
        }
        return render(result) ?? cutout
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
    private static func addBorder(to sticker: CIImage) -> CIImage {
        let width = max(sticker.extent.width, sticker.extent.height) * borderFraction
        let padded = sticker.transformed(by: CGAffineTransform(translationX: width * 2 - sticker.extent.minX, y: width * 2 - sticker.extent.minY))
        let canvas = CGRect(x: 0, y: 0, width: padded.extent.maxX + width * 2, height: padded.extent.maxY + width * 2)
        let white = CIFilter.colorMatrix()
        white.inputImage = padded
        white.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        white.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        white.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        white.biasVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        let grown = CIFilter.morphologyMaximum()
        grown.inputImage = white.outputImage?.premultiplyingAlpha()
        grown.radius = Float(width)
        guard let outline = grown.outputImage else { return padded }
        return padded.composited(over: outline).cropped(to: canvas)
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
}
