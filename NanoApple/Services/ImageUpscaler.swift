import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

actor ImageUpscaler {
    enum UpscaleError: LocalizedError {
        case unreadableImage
        case outputTooLarge
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .unreadableImage:
                String(localized: "upscale.error.unreadable", defaultValue: "L’image source ne peut pas être lue.")
            case .outputTooLarge:
                String(localized: "upscale.error.too_large", defaultValue: "L’image agrandie dépasserait 8192 pixels.")
            case .encodingFailed:
                String(localized: "upscale.error.encoding", defaultValue: "L’image agrandie n’a pas pu être enregistrée.")
            }
        }
    }

    func upscale(source: URL, factor: Int, outputDirectory: URL) throws -> URL {
        guard factor == 2 || factor == 4,
              let sourceProvider = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(sourceProvider, 0, [
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else {
            throw UpscaleError.unreadableImage
        }
        let width = image.width * factor
        let height = image.height * factor
        guard width <= 8_192, height <= 8_192 else { throw UpscaleError.outputTooLarge }

        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw UpscaleError.encodingFailed }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let output = context.makeImage() else { throw UpscaleError.encodingFailed }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let destination = outputDirectory.appending(
            path: "\(source.deletingPathExtension().lastPathComponent)-\(factor)x-\(UUID().uuidString.prefix(8)).png"
        )
        guard let writer = CGImageDestinationCreateWithURL(
            destination as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw UpscaleError.encodingFailed }
        CGImageDestinationAddImage(writer, output, nil)
        guard CGImageDestinationFinalize(writer) else { throw UpscaleError.encodingFailed }
        return destination
    }
}
