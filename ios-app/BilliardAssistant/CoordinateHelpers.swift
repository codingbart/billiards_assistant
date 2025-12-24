import SwiftUI

struct CoordinateHelpers {
    static func calculateScaleAndOffset(imageSize: CGSize, viewSize: CGSize) -> (scale: CGFloat, offset: CGPoint) {
        guard imageSize.width > 0 else { return (0, .zero) }
        let widthScale = viewSize.width / imageSize.width
        let heightScale = viewSize.height / imageSize.height
        let scale = min(widthScale, heightScale)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return (scale, CGPoint(x: (viewSize.width - scaledSize.width)/2, y: (viewSize.height - scaledSize.height)/2))
    }
    
    static func convertFromViewToImage(point: CGPoint, imageSize: CGSize, viewSize: CGSize) -> Point? {
        let (scale, offset) = calculateScaleAndOffset(imageSize: imageSize, viewSize: viewSize)
        return Point(x: Int((point.x - offset.x) / scale), y: Int((point.y - offset.y) / scale))
    }
    
    static func convert(_ p: CGPoint, _ scale: CGFloat, _ offset: CGPoint) -> CGPoint {
        return CGPoint(x: p.x * scale + offset.x, y: p.y * scale + offset.y)
    }
}

