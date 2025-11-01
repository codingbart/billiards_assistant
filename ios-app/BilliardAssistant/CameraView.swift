import SwiftUI

struct CameraView: View {
    // Stany obrazu i selekcji
    @State private var capturedImage: UIImage? = UIImage(named: "test.jpg")
    
    // Pozycje na EKRANIE (do rysowania kropek)
    @State private var targetBallPosition: CGPoint?
    @State private var pocketPosition: CGPoint?
    
    // Przeliczone pozycje na OBRAZIE (do wysłania do serwera)
    @State private var targetBallPoint: Point?
    @State private var pocketPoint: Point?
    
    // Stany sieciowe
    @State private var networkManager = NetworkManager()
    @State private var analysisResult: AnalysisResult?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // Stany lupy
    @GestureState private var dragLocation: CGPoint = .zero
    @State private var isDragging = false
    
    var body: some View {
        let loupeOffset: CGFloat = -100.0
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            GeometryReader { geometry in
                // Obliczamy skalę i ramkę obrazka na ekranie
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
                        
                        // Rysowanie znaczników
                        if let targetBallPosition {
                            Circle().fill(Color.red.opacity(0.7)).frame(width: 20, height: 20).position(targetBallPosition)
                        }
                        if let pocketPosition {
                            Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.green.opacity(0.7))
                                .background(Color.white.opacity(0.5).clipShape(Circle()))
                                .frame(width: 30, height: 30).position(pocketPosition)
                        }
                        
                        // Rysowanie linii
                        if let result = analysisResult {
                            drawAnalysisLines(result: result, scale: scale, offset: offset)
                        }
                        
                        // Lupa
                        if isDragging {
                            MagnifyingLoupeView(
                                image: image,
                                touchPoint: dragLocation,
                                imageFrame: imageFrame
                            )
                            .position(x: dragLocation.x, y: dragLocation.y + loupeOffset)
                        }
                        
                    }
                } // Koniec ZStack obrazka
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
                            
                            // Przekazujemy rozmiar geometrii do funkcji handleSelection
                            handleSelection(at: clampedLocation, in: geometry.size)
                        }
                )
            } // Koniec GeometryReader
            
            // Dolny przycisk
            VStack {
                if let errorMessage {
                    Text(errorMessage).padding().background(Color.red).foregroundColor(.white).cornerRadius(10)
                }
                Spacer()
                Button(action: sendAnalysisRequest) {
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
    
    // MARK: - Funkcje Logiki
    
    func handleSelection(at location: CGPoint, in viewSize: CGSize) {
        guard let image = capturedImage else { return }
        
        guard let imagePoint = convertFromViewToImage(point: location, imageSize: image.size, viewSize: viewSize) else {
            print("Puszczono palec poza obrazkiem")
            return
        }
        
        if targetBallPosition == nil {
            targetBallPosition = location
            targetBallPoint = imagePoint
        } else if pocketPosition == nil {
            pocketPosition = location
            pocketPoint = imagePoint
        } else {
            // Resetuj
            targetBallPosition = location
            targetBallPoint = imagePoint
            pocketPosition = nil
            pocketPoint = nil
        }
    }
    
    func sendAnalysisRequest() {
        guard let image = capturedImage else { self.errorMessage = "Brak obrazu"; return }
        
        guard let targetPoint = targetBallPoint else { self.errorMessage = "Wybierz bilę"; return }
        guard let pocketPoint = pocketPoint else { self.errorMessage = "Wybierz łuzę"; return }
        
        isLoading = true
        errorMessage = nil
        analysisResult = nil
        
        networkManager.analyzeImage(image: image, targetBall: targetPoint, pocket: pocketPoint) { result in
            isLoading = false
            switch result {
            case .success(let analysis):
                self.analysisResult = analysis
            case .failure(let error):
                self.errorMessage = "Błąd analizy: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Funkcje Pomocnicze (Z RYSOWANIEM GHOST BALL)
    
    @ViewBuilder
    func drawAnalysisLines(result: AnalysisResult, scale: CGFloat, offset: CGPoint) -> some View {
        
        // 1. Narysuj linię BILA -> ŁUZA (linia[0], zielona, ciągła)
        if let line = result.shot_lines.first {
            let startPoint = convertFromImageToView(point: line.start, scale: scale, offset: offset)
            let endPoint = convertFromImageToView(point: line.end, scale: scale, offset: offset)
            Path { path in
                path.move(to: startPoint)
                path.addLine(to: endPoint)
            }
            .stroke(Color.green.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        
        // 2. Narysuj linię BIAŁA -> BILA DUCH (linia[1], czerwona, przerywana)
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
        
        // === POPRAWKA ===
        // 3. Rysuj bilę ducha (przywrócone)
        let ghostBall = result.ghost_ball
        let centerPoint = convertFromImageToView(point: ghostBall.center, scale: scale, offset: offset)
        let radius = CGFloat(ghostBall.radius) * scale
        
        Circle()
            .stroke(Color.cyan.opacity(0.7), lineWidth: 3)
            .frame(width: radius * 2, height: radius * 2)
            .position(centerPoint)
    }
    
    // --- Reszta funkcji pomocniczych (bez zmian) ---
    
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
