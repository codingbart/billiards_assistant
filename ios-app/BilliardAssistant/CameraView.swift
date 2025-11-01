import SwiftUI

struct CameraView: View {
    // Stany obrazu i selekcji
    @State private var capturedImage: UIImage? = UIImage(named: "test.jpg")
    @State private var targetBallPosition: CGPoint? // Pozycja kropki na EKRANIE
    @State private var pocketPosition: CGPoint?   // Pozycja X na EKRANIE
    
    // Stany sieciowe
    @State private var networkManager = NetworkManager()
    @State private var analysisResult: AnalysisResult?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // --- NOWE STANY DO OBSŁUGI LUPY ---
    @GestureState private var dragLocation: CGPoint = .zero // Aktualna pozycja palca
    @State private var isDragging = false // Czy palec jest na ekranie
    
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
                        
                        // Rysowanie znaczników (bez zmian)
                        if let targetBallPosition {
                            Circle().fill(Color.red.opacity(0.7)).frame(width: 20, height: 20).position(targetBallPosition)
                        }
                        if let pocketPosition {
                            Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.green.opacity(0.7))
                                .background(Color.white.opacity(0.5).clipShape(Circle()))
                                .frame(width: 30, height: 30).position(pocketPosition)
                        }
                        
                        // Rysowanie linii (bez zmian)
                        if let result = analysisResult {
                            drawAnalysisLines(result: result, scale: scale, offset: offset)
                        }
                        
                        // --- NOWA LUPA (POWIĘKSZENIE) ---
                        if isDragging {
                            MagnifyingLoupeView(
                                image: image,
                                touchPoint: dragLocation, // Aktualna pozycja palca
                                imageFrame: imageFrame    // Ramka obrazka
                            )
                            // Przesuń lupę 100 punktów NAD palec
                            .position(x: dragLocation.x, y: dragLocation.y + loupeOffset)
                        }
                        
                    }
                } // Koniec ZStack obrazka
                // --- ZMIANA GESTU ---
                // Usuwamy .onTapGesture i dodajemy .gesture(DragGesture...)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .updating($dragLocation) { value, state, _ in
                            state = value.location // Aktualizuje pozycję przeciągania
                        }
                        .onChanged { _ in
                            if !self.isDragging {
                                // To jest początek dotyku
                                self.isDragging = true
                                self.analysisResult = nil // Wyczyść stare linie
                                self.errorMessage = nil
                            }
                        }
                        .onEnded { value in
                            self.isDragging = false // Ukryj lupę
                            
                            // --- POPRAWIONA LOGIKA ZAPISU ---
                            
                            // 1. Oblicz pozycję KRZYŻYKA lupy (pozycja palca + przesunięcie)
                            let loupeCrosshairLocation = CGPoint(x: value.location.x, y: value.location.y + loupeOffset)
                            
                            // 2. "Przyklej" pozycję KRZYŻYKA do krawędzi obrazka
                            let clampedX = min(max(loupeCrosshairLocation.x, imageFrame.minX), imageFrame.maxX)
                            let clampedY = min(max(loupeCrosshairLocation.y, imageFrame.minY), imageFrame.maxY)
                            let clampedLocation = CGPoint(x: clampedX, y: clampedY)
                            
                            // 3. Zapisz tę "przyklejoną" pozycję krzyżyka (a nie palca!)
                            handleSelection(at: clampedLocation, in: geometry.size)
                        }
                )
            } // Koniec GeometryReader
            
            // Dolny przycisk (bez zmian)
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
    
    // Zmieniamy handleTap na handleSelection
    func handleSelection(at location: CGPoint, in viewSize: CGSize) {
        guard let image = capturedImage else { return }
        
        // Sprawdź, czy kliknięcie było na obrazku
        guard let _ = convertFromViewToImage(point: location, imageSize: image.size, viewSize: viewSize) else {
            print("Puszczono palec poza obrazkiem")
            return
        }
        
        if targetBallPosition == nil {
            targetBallPosition = location // Zapisz pozycję EKRANOWĄ
        } else if pocketPosition == nil {
            pocketPosition = location
        } else {
            // Resetuj
            targetBallPosition = location
            pocketPosition = nil
        }
    }
    
    func sendAnalysisRequest() {
        let viewSize = UIScreen.main.bounds.size
        guard let image = capturedImage else { self.errorMessage = "Brak obrazu"; return }
        guard let targetBallTap = targetBallPosition else { self.errorMessage = "Wybierz bilę"; return }
        guard let pocketTap = pocketPosition else { self.errorMessage = "Wybierz łuzę"; return }
        
        guard let targetPoint = convertFromViewToImage(point: targetBallTap, imageSize: image.size, viewSize: viewSize),
              let pocketPoint = convertFromViewToImage(point: pocketTap, imageSize: image.size, viewSize: viewSize) else {
            self.errorMessage = "Błąd konwersji współrzędnych"; return
        }
        
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
    
    // --- FUNKCJE POMOCNICZE (bez zmian) ---
    
    // Funkcja do rysowania linii (wydzielona dla czystości)
    // MARK: - Funkcje Pomocnicze (POPRAWIONE RYSOWANIE)
    
    @ViewBuilder
    func drawAnalysisLines(result: AnalysisResult, scale: CGFloat, offset: CGPoint) -> some View {
        
        // --- POPRAWIONA LOGIKA RYSOWANIA ---
        
        // 1. Narysuj linię BILA -> ŁUZA (linia[0], zielona, ciągła)
        // Zakładamy, że pierwsza linia w tablicy to linia strzału bili
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
        // Zakładamy, że druga linia to linia celowania
        if result.shot_lines.count > 1 {
            let line = result.shot_lines[1]
            let startPoint = convertFromImageToView(point: line.start, scale: scale, offset: offset)
            let endPoint = convertFromImageToView(point: line.end, scale: scale, offset: offset)
            
            Path { path in
                path.move(to: startPoint)
                path.addLine(to: endPoint)
            }
            // To jest linia CELOWANIA, więc jest czerwona i przerywana
            .stroke(Color.red.opacity(0.8), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [10, 5]))
        }
        // ------------------------------------
        
        // Rysuj bilę ducha (bez zmian)
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
        // ... (bez zmian) ...
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
        // ... (bez zmian) ...
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
        // ... (bez zmian) ...
        let viewX = (CGFloat(point.x) * scale) + offset.x
        let viewY = (CGFloat(point.y) * scale) + offset.y
        return CGPoint(x: viewX, y: viewY)
    }
}
