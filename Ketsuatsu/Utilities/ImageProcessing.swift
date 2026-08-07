import UIKit

/// 画像の縮小まわり。写真をそのまま持つとメモリを圧迫するので、
/// 保存用・一覧表示用にサイズを落として扱う。
enum ImageProcessing {

    /// 保存用に長辺 1600px 程度へ縮小した JPEG を作る。
    static func jpegData(from image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image.jpegData(compressionQuality: quality) }
        return resized(image, maxDimension: maxDimension).jpegData(compressionQuality: quality)
    }

    /// 一覧に並べるための小さな画像。
    static func thumbnail(from image: UIImage, maxDimension: CGFloat = 240) -> UIImage {
        resized(image, maxDimension: maxDimension)
    }

    static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension, longest > 0 else { return image }

        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
