import UIKit

enum ImageUtils {
    /// Redimensionne (côté max) et compresse en JPEG.
    static func jpeg(_ image: UIImage, maxSide: CGFloat, quality: CGFloat = 0.75) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let img = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return img.jpegData(compressionQuality: quality)
    }
}
