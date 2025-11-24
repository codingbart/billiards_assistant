import SwiftUI

struct CameraView: View {
    
    @State private var capturedImage: UIImage?
    
    @StateObject private var cameraCoordinator = CameraViewController.Coordinator()
    @State private var isAutoMode = true
    @State private var whiteBallPosition: CGPoint?
    @State private var targetBallPosition: CGPoint?
    @State private var pocketPosition: CGPoint?
    
    @State private var whiteBallPoint: Point?
    @State private var targetBallPoint: Point?
    @State private var pocketPoint: Point?
    
    @State private var networkManager = NetworkManager()
    @State private var analysisResult: AnalysisResult?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    @GestureState private var dragLocation: CGPoint = .zero
    @State private var isDragging = false
    
    var body: some View {
        let loupeOffset: CGFloat = -100.0
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if capturedImage == nil {
                CameraViewController(capturedImage: $capturedImage, coordinator: cameraCoordinator)
                    .edgesIgnoringSafeArea(.all)
            } else {
                GeometryReader { geometry in
                    let (scale, offset) = calculateScaleAndOffset(imageSize: capturedImage?.size ?? .zero, viewSize: geometry.size)
                    let imageFrame = CGRect(
                        x: offset.x,
                        y: offset.y,
                        width: (capturedImage?.size.width ?? 0) * scale,
                        height: (capturedImage?.size.height ?? 0) * scale
                    )
                    
                    ZStack {
                        if let image = capturedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                            
                            if let whiteBallPosition {
                                Circle().fill(Color.blue.opacity(0.7)).frame(width: 20, height: 20).position(whiteBallPosition)
                            }
                            if let targetBallPosition {
                                Circle().fill(Color.red.opacity(0.7)).frame(width: 20, height: 20).position(targetBallPosition)
                            }
                            if let pocketPosition {
                                Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.green.opacity(0.7))
                                    .background(Color.white.opacity(0.5).clipShape(Circle()))
                                    .frame(width: 30, height: 30).position(pocketPosition)
                            }
                            
                            if let result = analysisResult {
                                drawAnalysisLines(result: result, scale: scale, offset: offset)
                            }
                            
                            if isDragging {
                                MagnifyingLoupeView(
                                    image: image,
                                    touchPoint: dragLocation,
                                    imageFrame: imageFrame
                                )
                                .position(x: dragLocation.x, y: dragLocation.y + loupeOffset)
                            }
                        }
                    } 
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .updating($dragLocation) { value, state, _ in
                                state = value.location
                            }
                            .onChanged { _ in
                                if !self.isDragging {
                                    self.isDragging = true
                                    self.analysisResult = nil 
                                    self.errorMessage = nil
                                }
                            }
                            .onEnded { value in
                                self.isDragging = false
                                
                                let loupeCrosshairLocation = CGPoint(x: value.location.x, y: value.location.y + loupeOffset)
                                
                                let clampedX = min(max(loupeCrosshairLocation.x, imageFrame.minX), imageFrame.maxX)
                                let clampedY = min(max(loupeCrosshairLocation.y, imageFrame.minY), imageFrame.maxY)
                                let clampedLocation = CGPoint(x: clampedX, y: clampedY)
                                
                                handleSelection(at: clampedLocation, in: geometry.size)
                            }
                    )
                } 
            }
            
            VStack {
                if capturedImage != nil {
                    HStack {
                        Button(action: {
                            resetAll()
                        }) {
                            Image(systemName: "arrow.left")
                                .font(.title)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding(.leading)
                        
                        Spacer()
                    }
                    .padding(.top, 50)
                }
                
                if capturedImage != nil {
                    if let errorMessage {
                        Text(errorMessage).padding().background(Color.red).foregroundColor(.white).cornerRadius(10)
                    }
                    
                    VStack {
                        Toggle("Tryb Automatyczny (AI)", isOn: $isAutoMode.animation())
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        
                        Text(getInstructionText())
                            .foregroundColor(.white)
                            .font(.footnote)
                            .padding(8)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(8)
                    }
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(10)
                    .padding(.top, 30)
                }
                
                Spacer()
                
                Button(action: {
                    if capturedImage == nil {
                        cameraCoordinator.capturePhoto()
                    } else {
                        sendAnalysisRequest()
                    }
                }) {
                    ZStack {
                        Circle().fill(Color.white).frame(width: 65, height: 65)
                        Circle().stroke(Color.white, lineWidth: 4).frame(width: 75, height: 75)
                        if isLoading {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .blue)).scaleEffect(2.0)
                        }
                    }
                }
                .padding(.bottom, 30)
                .disabled(isLoading)
            }
        }
    }
    
    
    func resetAll() {
        capturedImage = nil
        analysisResult = nil
        errorMessage = nil
        isLoading = false
        
        whiteBallPosition = nil
        targetBallPosition = nil
        pocketPosition = nil
        
        whiteBallPoint = nil
        targetBallPoint = nil
        pocketPoint = nil
    }

    func handleSelection(at location: CGPoint, in viewSize: CGSize) {
        guard let image = capturedImage else { return }
        
        guard let imagePoint = convertFromViewToImage(point: location, imageSize: image.size, viewSize: viewSize) else {
            print("Puszczono palec poza obrazkiem")
            return
        }
        
        analysisResult = nil
        errorMessage = nil

        if isAutoMode {
            if targetBallPosition == nil {
                targetBallPosition = location
                targetBallPoint = imagePoint
                pocketPosition = nil
                pocketPoint = nil
            } else if pocketPosition == nil {
                pocketPosition = location
                pocketPoint = imagePoint
            } else {
                targetBallPosition = location
                targetBallPoint = imagePoint
                pocketPosition = nil
                pocketPoint = nil
            }
            whiteBallPosition = nil
            whiteBallPoint = nil
            
        } else {
            if whiteBallPosition == nil {
                whiteBallPosition = location
                whiteBallPoint = imagePoint
                targetBallPosition = nil
                targetBallPoint = nil
                pocketPosition = nil
                pocketPoint = nil
                
            } else if targetBallPosition == nil {
                targetBallPosition = location
                targetBallPoint = imagePoint
                
            } else if pocketPosition == nil {
                pocketPosition = location
                pocketPoint = imagePoint
                
            } else {
                whiteBallPosition = location
                whiteBallPoint = imagePoint
                targetBallPosition = nil
                targetBallPoint = nil
                pocketPosition = nil
                pocketPoint = nil
            }
        }
    }
    
    func sendAnalysisRequest() {
        isLoading = true
        errorMessage = nil
        
        if isAutoMode {
            guard let image = capturedImage else { self.errorMessage = "Brak obrazu"; isLoading = false; return }
            guard let targetPoint = targetBallPoint else { self.errorMessage = "Wybierz bilę DOCELOWĄ"; isLoading = false; return }
            guard let pocketPoint = pocketPoint else { self.errorMessage = "Wybierz ŁUZĘ"; isLoading = false; return }
            
            networkManager.analyzeImage(image: image, targetBall: targetPoint, pocket: pocketPoint) { result in
                isLoading = false
                switch result {
                case .success(let analysis):
                    self.analysisResult = analysis
                    self.whiteBallPosition = nil
                    self.targetBallPosition = nil
                    self.pocketPosition = nil
                case .failure(let error):
                    if let networkError = error as? NetworkError {
                        self.errorMessage = networkError.errorDescription ?? "Błąd analizy AI"
                    } else {
                        self.errorMessage = "Błąd analizy AI: \(error.localizedDescription)"
                    }
                }
            }
            
        } else {
            guard let whitePoint = whiteBallPoint else { self.errorMessage = "Wybierz BIAŁĄ bilę"; isLoading = false; return }
            guard let targetPoint = targetBallPoint else { self.errorMessage = "Wybierz bilę DOCELOWĄ"; isLoading = false; return }
            guard let pocketPoint = pocketPoint else { self.errorMessage = "Wybierz ŁUZĘ"; isLoading = false; return }
            
            networkManager.calculateManual(whiteBall: whitePoint, targetBall: targetPoint, pocket: pocketPoint) { result in
                isLoading = false
                switch result {
                case .success(let analysis):
                    self.analysisResult = analysis
                    self.whiteBallPosition = nil
                    self.targetBallPosition = nil
                    self.pocketPosition = nil
                case .failure(let error):
                    if let networkError = error as? NetworkError {
                        self.errorMessage = networkError.errorDescription ?? "Błąd analizy ręcznej"
                    } else {
                        self.errorMessage = "Błąd analizy ręcznej: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    
    func getInstructionText() -> String {
        if isAutoMode {
            if targetBallPoint == nil {
                return "Tryb AI: Wybierz BILĘ DOCELOWĄ"
            } else if pocketPoint == nil {
                return "Tryb AI: Wybierz ŁUZĘ"
            } else {
                return "Gotowy do analizy!"
            }
        } else {
            if whiteBallPoint == nil {
                return "Tryb Ręczny: Wybierz BIAŁĄ BILĘ"
            } else if targetBallPoint == nil {
                return "Tryb Ręczny: Wybierz BILĘ DOCELOWĄ"
            } else if pocketPoint == nil {
                return "Tryb Ręczny: Wybierz ŁUZĘ"
            } else {
                return "Gotowy do analizy!"
            }
        }
    }
    
    @ViewBuilder
    func drawAnalysisLines(result: AnalysisResult, scale: CGFloat, offset: CGPoint) -> some View {
        if let line = result.shot_lines.first {
            let startPoint = convertFromImageToView(point: line.start, scale: scale, offset: offset)
            let endPoint = convertFromImageToView(point: line.end, scale: scale, offset: offset)
            Path { path in
                path.move(to: startPoint)
                path.addLine(to: endPoint)
            }
            .stroke(Color.green.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        
        if result.shot_lines.count > 1 {
            let line = result.shot_lines[1]
            let startPoint = convertFromImageToView(point: line.start, scale: scale, offset: offset)
            let endPoint = convertFromImageToView(point: line.end, scale: scale, offset: offset)
            
            Path { path in
                path.move(to: startPoint)
                path.addLine(to: endPoint)
            }
            .stroke(Color.red.opacity(0.8), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [10, 5]))
        }
        
        let ghostBall = result.ghost_ball
        let centerPoint = convertFromImageToView(point: ghostBall.center, scale: scale, offset: offset)
        let radius = CGFloat(ghostBall.radius) * scale
        
        Circle()
            .stroke(Color.cyan.opacity(0.7), lineWidth: 3)
            .frame(width: radius * 2, height: radius * 2)
            .position(centerPoint)
    }
    
    func calculateScaleAndOffset(imageSize: CGSize, viewSize: CGSize) -> (scale: CGFloat, offset: CGPoint) {
        guard imageSize.width > 0, imageSize.height > 0 else { return (0, .zero) }
        let widthScale = viewSize.width / imageSize.width
        let heightScale = viewSize.height / imageSize.height
        let scale = min(widthScale, heightScale)
        let scaledImageSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let offsetX = (viewSize.width - scaledImageSize.width) / 2
        let offsetY = (viewSize.height - scaledImageSize.height) / 2
        return (scale, CGPoint(x: offsetX, y: offsetY))
    }
    
    func convertFromViewToImage(point: CGPoint, imageSize: CGSize, viewSize: CGSize) -> Point? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        let (scale, offset) = calculateScaleAndOffset(imageSize: imageSize, viewSize: viewSize)
        let imageX = (point.x - offset.x) / scale
        let imageY = (point.y - offset.y) / scale
        if imageX >= 0 && imageX <= imageSize.width && imageY >= 0 && imageY <= imageSize.height {
            return Point(x: Int(imageX), y: Int(imageY))
        }
        return nil
    }
    
    func convertFromImageToView(point: Point, scale: CGFloat, offset: CGPoint) -> CGPoint {
        let viewX = (CGFloat(point.x) * scale) + offset.x
        let viewY = (CGFloat(point.y) * scale) + offset.y
        return CGPoint(x: viewX, y: viewY)
    }
}
