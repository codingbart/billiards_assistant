import SwiftUI

struct MagnifyingLoupeView: View {
    let image: UIImage
    let touchPoint: CGPoint 
    let imageFrame: CGRect 
    
    var body: some View {
        let loupeSize: CGFloat = 110 
        let magnification: CGFloat = 2.5 

        let relativeX = (touchPoint.x - imageFrame.origin.x) / imageFrame.width
        let relativeY = (touchPoint.y - imageFrame.origin.y) / imageFrame.height

        let clampedRelativeX = min(max(relativeX, 0), 1)
        let clampedRelativeY = min(max(relativeY, 0), 1)

        return AnyView(
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill() 
                    .frame(width: imageFrame.width * magnification, height: imageFrame.height * magnification)
                
                    .offset(
                            x: -clampedRelativeX * (imageFrame.width * magnification) + (loupeSize / 2),
                            y: -clampedRelativeY * (imageFrame.height * magnification) + (loupeSize / 2)
                    )
            }
            .frame(width: loupeSize, height: loupeSize) 
            .clipShape(Circle()) 
            .overlay(
                ZStack {
                    Circle().stroke(Color.primary, lineWidth: 2)
                    Rectangle().fill(Color.red).frame(width: 1, height: loupeSize) 
                    Rectangle().fill(Color.red).frame(width: loupeSize, height: 1) 
                }
            )
            .shadow(radius: 5) 
        )
    }
}
