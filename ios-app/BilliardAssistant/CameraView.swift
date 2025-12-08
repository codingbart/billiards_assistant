import SwiftUI

struct CameraView: View {
    
    @State private var capturedImage: UIImage?
    @StateObject private var cameraCoordinator = CameraViewController.Coordinator()
    
    // Lista zaznaczonych łuz
    @State private var pockets: [CGPoint] = []
    // Wynik z serwera
    @State private var bestShotResult: BestShotResult?
    
    // Obszar stołu (narożniki przekątnej prostokąta)
    @State private var tableAreaStart: CGPoint? = nil
    @State private var tableAreaEnd: CGPoint? = nil
    
    // Tryby edycji
    @State private var isSelectingTableArea = false
    @State private var showAllDetectedBalls = true  // Przełącznik wyświetlania wszystkich wykrytych bil
    
    // Domyślny kolor bili rozgrywającej
    @State private var cueBallColor = "Red"
    let availableColors = ["White", "Red", "Yellow", "Blue", "Green", "Orange", "Purple", "Black", "Brown"]
    
    @State private var networkManager = NetworkManager()
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if capturedImage == nil {
                // --- TRYB APARATU ---
                CameraViewController(capturedImage: $capturedImage, coordinator: cameraCoordinator)
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        VStack {
                            Spacer()
                            Text("Ustaw kamerę prosto nad stołem")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(10)
                                .padding(.bottom, 100)
                        }
                    )
                
                VStack {
                    Spacer()
                    Button(action: { cameraCoordinator.capturePhoto() }) {
                        ZStack {
                            Circle().fill(Color.white).frame(width: 70, height: 70)
                            Circle().stroke(Color.black, lineWidth: 2).frame(width: 60, height: 60)
                        }
                    }.padding(.bottom, 30)
                }
                
            } else {
                // --- TRYB EDYCJI / ANALIZY ---
                GeometryReader { geometry in
                    let (scale, offset) = calculateScaleAndOffset(imageSize: capturedImage?.size ?? .zero, viewSize: geometry.size)
                    
                    ZStack {
                        if let image = capturedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                                
                                // GESTY
                                .gesture(
                                    // 1. Kliknięcie (Tap) do dodawania łuz
                                    // Używamy DragGesture z minDistance 0, aby pobrać lokalizację.
                                    // Poprawka: Dodano tolerancję ruchu < 10 punktów.
                                    DragGesture(minimumDistance: 0)
                                        .onEnded { value in
                                            // Sprawdzamy, czy to było kliknięcie (małe przesunięcie)
                                            if abs(value.translation.width) < 10 && abs(value.translation.height) < 10 {
                                                // Dodajemy łuzę TYLKO gdy NIE zaznaczamy obszaru
                                                if !isSelectingTableArea && bestShotResult == nil {
                                                    if let imgPoint = convertFromViewToImage(point: value.startLocation, imageSize: image.size, viewSize: geometry.size) {
                                                        let p = CGPoint(x: imgPoint.x, y: imgPoint.y)
                                                        pockets.append(p)
                                                    }
                                                }
                                            }
                                        }
                                )
                                .simultaneousGesture(
                                    // 2. Przeciąganie do zaznaczania obszaru stołu
                                    DragGesture(minimumDistance: 5)
                                        .onChanged { value in
                                            if isSelectingTableArea && bestShotResult == nil {
                                                if let imgPointStart = convertFromViewToImage(point: value.startLocation, imageSize: image.size, viewSize: geometry.size) {
                                                    tableAreaStart = CGPoint(x: imgPointStart.x, y: imgPointStart.y)
                                                }
                                                if let imgPointEnd = convertFromViewToImage(point: value.location, imageSize: image.size, viewSize: geometry.size) {
                                                    tableAreaEnd = CGPoint(x: imgPointEnd.x, y: imgPointEnd.y)
                                                }
                                            }
                                        }
                                )
                            
                            // WIZUALIZACJA ŁUZ
                            ForEach(0..<pockets.count, id: \.self) { i in
                                let p = pockets[i]
                                let viewP = convertFromImageToView(point: Point(x: Int(p.x), y: Int(p.y)), scale: scale, offset: offset)
                                ZStack {
                                    Circle().fill(Color.black).frame(width: 24, height: 24)
                                    Circle().stroke(Color.green, lineWidth: 2).frame(width: 24, height: 24)
                                    Text("\(i+1)").font(.caption2).foregroundColor(.white)
                                }
                                .position(viewP)
                            }
                            
                            // WIZUALIZACJA OBSZARU STOŁU
                            if let start = tableAreaStart, let end = tableAreaEnd {
                                let viewStart = convertFromImageToView(point: Point(x: Int(start.x), y: Int(start.y)), scale: scale, offset: offset)
                                let viewEnd = convertFromImageToView(point: Point(x: Int(end.x), y: Int(end.y)), scale: scale, offset: offset)
                                
                                let rect = CGRect(
                                    x: min(viewStart.x, viewEnd.x),
                                    y: min(viewStart.y, viewEnd.y),
                                    width: abs(viewEnd.x - viewStart.x),
                                    height: abs(viewEnd.y - viewStart.y)
                                )
                                
                                Rectangle()
                                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 3, dash: [10]))
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                            }
                            
                            // WIZUALIZACJA WSZYSTKICH WYKRYTYCH BIL (dla debugowania)
                            if showAllDetectedBalls, let result = bestShotResult, let allDetected = result.all_detected_balls {
                                ForEach(0..<allDetected.count, id: \.self) { i in
                                    let ball = allDetected[i]
                                    let center = convertFromImageToView(
                                        point: Point(x: ball.x, y: ball.y),
                                        scale: scale,
                                        offset: offset
                                    )
                                    let radius = CGFloat(ball.r) * scale
                                    
                                    ZStack {
                                        Circle()
                                            .stroke(Color.orange.opacity(0.7), lineWidth: 2)
                                            .frame(width: radius * 2, height: radius * 2)
                                        VStack(spacing: 0) {
                                            Text(ball.ballClass)
                                                .font(.system(size: 7, weight: .bold))
                                                .foregroundColor(.white)
                                            Text(String(format: "%.0f%%", ball.confidence * 100))
                                                .font(.system(size: 6))
                                                .foregroundColor(.white.opacity(0.8))
                                        }
                                        .padding(2)
                                        .background(Color.orange.opacity(0.8))
                                        .cornerRadius(3)
                                    }
                                    .position(center)
                                }
                            }
                            
                            // WIZUALIZACJA WYNIKU
                            if let result = bestShotResult {
                                drawBestShot(result: result, scale: scale, offset: offset)
                            }
                        }
                    }
                }
                
                // PANEL STEROWANIA
                VStack {
                    // Góra: Wybór bili i przełącznik trybu
                    if bestShotResult == nil {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Bila rozgrywająca").font(.caption).foregroundColor(.gray)
                                Picker("Kolor", selection: $cueBallColor) {
                                    ForEach(availableColors, id: \.self) { color in
                                        Text(color).tag(color)
                                    }
                                }
                                .pickerStyle(.menu)
                                .accentColor(.white)
                                .background(Color.gray.opacity(0.3))
                                .cornerRadius(5)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                isSelectingTableArea.toggle()
                                if isSelectingTableArea {
                                    // Reset obszaru przy ponownym włączeniu, aby zacząć od nowa
                                    tableAreaStart = nil
                                    tableAreaEnd = nil
                                }
                            }) {
                                HStack {
                                    Image(systemName: isSelectingTableArea ? "checkmark.square.fill" : "rectangle.dashed")
                                    Text(isSelectingTableArea ? "Zakończ zaznaczanie" : "Zaznacz obszar")
                                }
                                .font(.caption)
                                .padding(8)
                                .background(isSelectingTableArea ? Color.yellow : Color.gray.opacity(0.5))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(Color.black.opacity(0.7))
                    }
                    
                    // Komunikaty
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(8)
                            .padding()
                    }
                    
                    if bestShotResult == nil {
                        Text(isSelectingTableArea ? "Przeciągnij palcem, aby otoczyć stół (tylko sukno)." : "Dotknij wszystkich łuz na zdjęciu.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.top, 5)
                    } else {
                        HStack {
                            if let angle = bestShotResult?.best_shot.angle {
                                Text("Najlepszy strzał: kąt \(String(format: "%.1f", angle))°")
                                    .font(.headline)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            
                            // Przycisk przełączania wyświetlania wszystkich wykrytych bil
                            if bestShotResult?.all_detected_balls != nil {
                                Button(action: { showAllDetectedBalls.toggle() }) {
                                    Image(systemName: showAllDetectedBalls ? "eye.fill" : "eye.slash.fill")
                                        .foregroundColor(.white)
                                        .padding(8)
                                        .background(showAllDetectedBalls ? Color.orange : Color.gray.opacity(0.5))
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Dół: Przyciski akcji
                    HStack {
                        Button(action: resetAll) {
                            VStack {
                                Image(systemName: "trash")
                                Text("Od nowa").font(.caption)
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        if bestShotResult == nil {
                            Button(action: scanTable) {
                                HStack {
                                    if isLoading {
                                        ProgressView().tint(.white)
                                    } else {
                                        Image(systemName: "scope")
                                        Text("ANALIZUJ")
                                    }
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 30)
                                .padding(.vertical, 15)
                                .background(pockets.count < 1 ? Color.gray : Color.blue)
                                .cornerRadius(25)
                            }
                            .disabled(pockets.isEmpty || isLoading)
                        }
                    }
                    .padding(30)
                }
            }
        }
    }
    
    // --- LOGIKA ---
    
    func scanTable() {
        guard let image = capturedImage else { return }
        
        var tableArea: [CGPoint]? = nil
        if let start = tableAreaStart, let end = tableAreaEnd {
            let xMin = min(start.x, end.x)
            let xMax = max(start.x, end.x)
            let yMin = min(start.y, end.y)
            let yMax = max(start.y, end.y)
            
            tableArea = [
                CGPoint(x: xMin, y: yMin), // Lewy-Góra
                CGPoint(x: xMax, y: yMin), // Prawy-Góra
                CGPoint(x: xMax, y: yMax), // Prawy-Dół
                CGPoint(x: xMin, y: yMax)  // Lewy-Dół
            ]
        }
        
        isLoading = true
        errorMessage = nil
        
        networkManager.analyzeBestShot(
            image: image,
            pockets: pockets,
            imageSize: image.size,
            tableArea: tableArea,
            cueBallColor: cueBallColor
        ) { result in
            isLoading = false
            switch result {
            case .success(let data):
                self.bestShotResult = data
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    func resetAll() {
        capturedImage = nil
        pockets.removeAll()
        bestShotResult = nil
        errorMessage = nil
        isLoading = false
        tableAreaStart = nil
        tableAreaEnd = nil
        isSelectingTableArea = false
        cueBallColor = "Red" 
    }
    
    @ViewBuilder
    func drawBestShot(result: BestShotResult, scale: CGFloat, offset: CGPoint) -> some View {
        let shot = result.best_shot
        
        // 1. Linia: Bila Cel -> Łuza (Ciągła Zielona)
        if let lineToPocket = shot.shot_lines.first {
            let start = convertFromImageToView(point: lineToPocket.start, scale: scale, offset: offset)
            let end = convertFromImageToView(point: lineToPocket.end, scale: scale, offset: offset)
            Path { p in p.move(to: start); p.addLine(to: end) }
                .stroke(Color.green, lineWidth: 4)
        }
        
        // 2. Linia: Bila Startowa -> Bila Duch (Przerywana Biała)
        if shot.shot_lines.count > 1 {
            let lineFromCue = shot.shot_lines[1]
            let start = convertFromImageToView(point: lineFromCue.start, scale: scale, offset: offset)
            let end = convertFromImageToView(point: lineFromCue.end, scale: scale, offset: offset)
            Path { p in p.move(to: start); p.addLine(to: end) }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, dash: [10]))
        }
        
        // 3. Bila Duch
        let ghostCenter = convertFromImageToView(point: shot.ghost_ball.center, scale: scale, offset: offset)
        let r = CGFloat(shot.ghost_ball.radius) * scale
        Circle()
            .stroke(Color.white, lineWidth: 2)
            .frame(width: r*2, height: r*2)
            .position(ghostCenter)
            
        // 4. Bila Startowa
        let cueCenter = convertFromImageToView(point: result.white_ball, scale: scale, offset: offset)
        Circle().fill(Color.blue).frame(width: 15, height: 15).position(cueCenter)
        
        // 5. Bila Cel
        let targetCenter = convertFromImageToView(point: shot.target_ball, scale: scale, offset: offset)
        Circle().fill(Color.red).frame(width: 15, height: 15).position(targetCenter)
    }
    
    // --- POMOCNICZE ---
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
        let clampedX = min(max(imageX, 0), imageSize.width)
        let clampedY = min(max(imageY, 0), imageSize.height)
        return Point(x: Int(clampedX), y: Int(clampedY))
    }
    
    func convertFromImageToView(point: Point, scale: CGFloat, offset: CGPoint) -> CGPoint {
        let viewX = (CGFloat(point.x) * scale) + offset.x
        let viewY = (CGFloat(point.y) * scale) + offset.y
        return CGPoint(x: viewX, y: viewY)
    }
    
    func convertFromImageToView(point: Ball, scale: CGFloat, offset: CGPoint) -> CGPoint {
        return convertFromImageToView(point: Point(x: point.x, y: point.y), scale: scale, offset: offset)
    }
}