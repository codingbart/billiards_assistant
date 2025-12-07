import SwiftUI

struct CameraView: View {
    
    @State private var capturedImage: UIImage?
    @StateObject private var cameraCoordinator = CameraViewController.Coordinator()
    
    // --- Nowe Stany ---
    @State private var pockets: [CGPoint] = [] // Lista zaznaczonych łuz
    @State private var bestShotResult: BestShotResult? // Wynik z serwera
    
    // Obszar stołu (4 narożniki prostokąta)
    @State private var tableAreaStart: CGPoint? = nil
    @State private var tableAreaEnd: CGPoint? = nil
    @State private var isSelectingTableArea = false
    @State private var isEditingTableArea = false
    @State private var dragHandle: TableAreaHandle? = nil // Który element jest przeciągany
    @State private var dragStartPoint: CGPoint? = nil // Punkt początkowy przeciągania (współrzędne obrazu)
    
    enum TableAreaHandle {
        case topLeft, topRight, bottomLeft, bottomRight, center
    }
    
    // Kolor bili cue
    @State private var cueBallColor = "White"
    let availableColors = ["White", "Red", "Yellow", "Blue", "Green", "Orange", "Purple", "Pink"]
    
    @State private var networkManager = NetworkManager()
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if capturedImage == nil {
                // 1. TRYB APARATU
                CameraViewController(capturedImage: $capturedImage, coordinator: cameraCoordinator)
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        VStack {
                            Spacer()
                            Text("Zrób zdjęcie stołu")
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(10)
                                .padding(.bottom, 80)
                        }
                    )
                
                // Przycisk migawki
                VStack {
                    Spacer()
                    Button(action: { cameraCoordinator.capturePhoto() }) {
                        Circle().stroke(Color.white, lineWidth: 4).frame(width: 75, height: 75)
                    }.padding(.bottom, 30)
                }
                
            } else {
                // 2. TRYB ANALIZY (Na zrobionym zdjęciu)
                GeometryReader { geometry in
                    let (scale, offset) = calculateScaleAndOffset(imageSize: capturedImage?.size ?? .zero, viewSize: geometry.size)
                    
                    ZStack {
                        if let image = capturedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                                // Obsługa kliknięć (dodawanie łuz) - tylko gdy nie zaznaczamy obszaru
                                .onTapGesture { location in
                                    if bestShotResult == nil && !isSelectingTableArea && !isEditingTableArea {
                                        if let imgPoint = convertFromViewToImage(point: location, imageSize: image.size, viewSize: geometry.size) {
                                            let p = CGPoint(x: imgPoint.x, y: imgPoint.y)
                                            pockets.append(p)
                                        }
                                    }
                                }
                                // Obsługa przeciągania - tylko gdy zaznaczamy lub edytujemy obszar
                                .gesture(
                                    DragGesture(minimumDistance: 5)
                                        .onChanged { value in
                                            if bestShotResult == nil {
                                                if isSelectingTableArea {
                                                    // Nowe zaznaczenie
                                                    if let imgPoint = convertFromViewToImage(point: value.startLocation, imageSize: image.size, viewSize: geometry.size) {
                                                        tableAreaStart = CGPoint(x: imgPoint.x, y: imgPoint.y)
                                                    }
                                                    if let imgPoint = convertFromViewToImage(point: value.location, imageSize: image.size, viewSize: geometry.size) {
                                                        tableAreaEnd = CGPoint(x: imgPoint.x, y: imgPoint.y)
                                                    }
                                                } else if isEditingTableArea, let start = tableAreaStart, let end = tableAreaEnd {
                                                    // Edycja istniejącego obszaru
                                                    if let imgPoint = convertFromViewToImage(point: value.location, imageSize: image.size, viewSize: geometry.size) {
                                                        if dragHandle == nil {
                                                            // Sprawdź, który element został kliknięty (tylko przy pierwszym onChanged)
                                                            let viewStart = convertFromImageToView(point: Point(x: Int(start.x), y: Int(start.y)), scale: scale, offset: offset)
                                                            let viewEnd = convertFromImageToView(point: Point(x: Int(end.x), y: Int(end.y)), scale: scale, offset: offset)
                                                            let rect = CGRect(
                                                                x: min(viewStart.x, viewEnd.x),
                                                                y: min(viewStart.y, viewEnd.y),
                                                                width: abs(viewEnd.x - viewStart.x),
                                                                height: abs(viewEnd.y - viewStart.y)
                                                            )
                                                            
                                                            let handleSize: CGFloat = 30
                                                            let startLoc = value.startLocation
                                                            
                                                            if abs(startLoc.x - rect.minX) < handleSize && abs(startLoc.y - rect.minY) < handleSize {
                                                                dragHandle = .topLeft
                                                                if let startImg = convertFromViewToImage(point: value.startLocation, imageSize: image.size, viewSize: geometry.size) {
                                                                    dragStartPoint = CGPoint(x: CGFloat(startImg.x), y: CGFloat(startImg.y))
                                                                }
                                                            } else if abs(startLoc.x - rect.maxX) < handleSize && abs(startLoc.y - rect.minY) < handleSize {
                                                                dragHandle = .topRight
                                                                if let startImg = convertFromViewToImage(point: value.startLocation, imageSize: image.size, viewSize: geometry.size) {
                                                                    dragStartPoint = CGPoint(x: CGFloat(startImg.x), y: CGFloat(startImg.y))
                                                                }
                                                            } else if abs(startLoc.x - rect.minX) < handleSize && abs(startLoc.y - rect.maxY) < handleSize {
                                                                dragHandle = .bottomLeft
                                                                if let startImg = convertFromViewToImage(point: value.startLocation, imageSize: image.size, viewSize: geometry.size) {
                                                                    dragStartPoint = CGPoint(x: CGFloat(startImg.x), y: CGFloat(startImg.y))
                                                                }
                                                            } else if abs(startLoc.x - rect.maxX) < handleSize && abs(startLoc.y - rect.maxY) < handleSize {
                                                                dragHandle = .bottomRight
                                                                if let startImg = convertFromViewToImage(point: value.startLocation, imageSize: image.size, viewSize: geometry.size) {
                                                                    dragStartPoint = CGPoint(x: CGFloat(startImg.x), y: CGFloat(startImg.y))
                                                                }
                                                            } else if rect.contains(startLoc) {
                                                                dragHandle = .center
                                                                if let startImg = convertFromViewToImage(point: value.startLocation, imageSize: image.size, viewSize: geometry.size) {
                                                                    dragStartPoint = CGPoint(x: CGFloat(startImg.x), y: CGFloat(startImg.y))
                                                                }
                                                            }
                                                        }
                                                        
                                                        // Aktualizuj pozycję na podstawie delty od początku przeciągania
                                                        if let handle = dragHandle, let dragStart = dragStartPoint {
                                                            let deltaX = imgPoint.x - dragStart.x
                                                            let deltaY = imgPoint.y - dragStart.y
                                                            
                                                            switch handle {
                                                            case .topLeft:
                                                                tableAreaStart = CGPoint(x: start.x + deltaX, y: start.y + deltaY)
                                                            case .topRight:
                                                                tableAreaEnd = CGPoint(x: end.x + deltaX, y: end.y + deltaY)
                                                            case .bottomLeft:
                                                                tableAreaStart = CGPoint(x: start.x + deltaX, y: start.y + deltaY)
                                                            case .bottomRight:
                                                                tableAreaEnd = CGPoint(x: end.x + deltaX, y: end.y + deltaY)
                                                            case .center:
                                                                tableAreaStart = CGPoint(x: start.x + deltaX, y: start.y + deltaY)
                                                                tableAreaEnd = CGPoint(x: end.x + deltaX, y: end.y + deltaY)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        .onEnded { value in
                                            if isSelectingTableArea {
                                                isSelectingTableArea = false
                                                isEditingTableArea = true // Po zaznaczeniu, włącz tryb edycji
                                            }
                                            dragHandle = nil
                                            dragStartPoint = nil
                                        }
                                )
                            
                            // Rysowanie zaznaczonych ŁUZ (zielone kółka)
                            ForEach(0..<pockets.count, id: \.self) { i in
                                let p = pockets[i]
                                let viewP = convertFromImageToView(point: Point(x: Int(p.x), y: Int(p.y)), scale: scale, offset: offset)
                                Circle()
                                    .fill(Color.green.opacity(0.6))
                                    .frame(width: 30, height: 30)
                                    .position(viewP)
                            }
                            
                            // Rysowanie obszaru stołu (niebieski prostokąt z uchwytami)
                            if let start = tableAreaStart, let end = tableAreaEnd {
                                let viewStart = convertFromImageToView(point: Point(x: Int(start.x), y: Int(start.y)), scale: scale, offset: offset)
                                let viewEnd = convertFromImageToView(point: Point(x: Int(end.x), y: Int(end.y)), scale: scale, offset: offset)
                                
                                let rect = CGRect(
                                    x: min(viewStart.x, viewEnd.x),
                                    y: min(viewStart.y, viewEnd.y),
                                    width: abs(viewEnd.x - viewStart.x),
                                    height: abs(viewEnd.y - viewStart.y)
                                )
                                
                                ZStack {
                                    // Tło prostokąta
                                    Rectangle()
                                        .fill(Color.blue.opacity(0.2))
                                    Rectangle()
                                        .stroke(Color.blue.opacity(0.8), lineWidth: 3)
                                    
                                    // Uchwyty do edycji (tylko w trybie edycji)
                                    if isEditingTableArea {
                                        // Narożniki
                                        Circle().fill(Color.orange).frame(width: 20, height: 20).position(x: rect.minX, y: rect.minY)
                                        Circle().fill(Color.orange).frame(width: 20, height: 20).position(x: rect.maxX, y: rect.minY)
                                        Circle().fill(Color.orange).frame(width: 20, height: 20).position(x: rect.minX, y: rect.maxY)
                                        Circle().fill(Color.orange).frame(width: 20, height: 20).position(x: rect.maxX, y: rect.maxY)
                                    }
                                }
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                            }
                            
                            // Rysowanie WYNIKU (jeśli jest)
                            if let result = bestShotResult {
                                drawBestShot(result: result, scale: scale, offset: offset)
                            }
                        }
                    }
                }
                
                // Interfejs (Przyciski na dole)
                VStack {
                    // Górny panel - wybór koloru bili cue
                    if bestShotResult == nil {
                        HStack {
                            Text("Bila cue:")
                                .foregroundColor(.white)
                                .font(.caption)
                            
                            Picker("Kolor", selection: $cueBallColor) {
                                ForEach(availableColors, id: \.self) { color in
                                    Text(color).tag(color)
                                }
                            }
                            .pickerStyle(.menu)
                            .foregroundColor(.white)
                            .background(Color.blue.opacity(0.7))
                            .cornerRadius(8)
                            
                            Spacer()
                            
                            // Przycisk zaznaczania/edycji obszaru stołu
                            Button(action: {
                                if tableAreaStart != nil && tableAreaEnd != nil {
                                    // Jeśli obszar już istnieje, przełącz tryb edycji
                                    isEditingTableArea.toggle()
                                    isSelectingTableArea = false
                                } else {
                                    // Jeśli nie ma obszaru, zacznij zaznaczanie
                                    isSelectingTableArea.toggle()
                                    isEditingTableArea = false
                                }
                                if !isSelectingTableArea && !isEditingTableArea {
                                    tableAreaStart = nil
                                    tableAreaEnd = nil
                                }
                            }) {
                                HStack {
                                    Image(systemName: (isSelectingTableArea || isEditingTableArea) ? "checkmark.square.fill" : "square")
                                    Text(isSelectingTableArea ? "Zaznacz" : (isEditingTableArea ? "Edytuj obszar" : "Obszar stołu"))
                                        .font(.caption)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background((isSelectingTableArea || isEditingTableArea) ? Color.orange.opacity(0.8) : Color.gray.opacity(0.7))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    }
                    
                    // Instrukcje / Błędy
                    if let errorMessage {
                        Text(errorMessage).padding().background(Color.red).foregroundColor(.white).cornerRadius(10)
                    } else if bestShotResult == nil {
                        if isSelectingTableArea {
                            Text("Przeciągnij, aby zaznaczyć obszar stołu")
                                .padding().background(Color.orange.opacity(0.8)).foregroundColor(.white).cornerRadius(10)
                        } else if isEditingTableArea {
                            Text("Przeciągnij narożniki lub środek, aby dopasować obszar")
                                .padding().background(Color.orange.opacity(0.8)).foregroundColor(.white).cornerRadius(10)
                        } else {
                            Text("Kliknij na wszystkie łuzy (\(pockets.count))")
                                .padding().background(Color.black.opacity(0.5)).foregroundColor(.white).cornerRadius(10)
                        }
                    } else {
                        Text("Najłatwiejszy strzał (Kąt: \(String(format: "%.1f", bestShotResult!.best_shot.angle))°)")
                            .padding().background(Color.green).foregroundColor(.white).cornerRadius(10)
                    }
                    
                    Spacer()
                    
                    HStack {
                        // Przycisk "Reset / Nowe zdjęcie"
                        Button(action: resetAll) {
                            Image(systemName: "trash").font(.title).foregroundColor(.white)
                                .padding().background(Color.red.opacity(0.8)).clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        // Przycisk "Skanuj" (aktywny tylko gdy są łuzy)
                        if bestShotResult == nil {
                            Button(action: scanTable) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 20).fill(Color.blue).frame(width: 150, height: 50)
                                    if isLoading {
                                        ProgressView().tint(.white)
                                    } else {
                                        Text("SKANUJ STÓŁ").foregroundColor(.white).bold()
                                    }
                                }
                            }
                            .disabled(pockets.isEmpty || isLoading)
                            .opacity(pockets.isEmpty ? 0.5 : 1.0)
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)
                }
            }
        }
    }
    
    // --- FUNKCJE ---
    
    func scanTable() {
        guard let image = capturedImage else { return }
        isLoading = true
        errorMessage = nil
        
        // Przygotuj obszar stołu (4 narożniki prostokąta)
        var tableArea: [CGPoint]? = nil
        if let start = tableAreaStart, let end = tableAreaEnd {
            // Tworzymy 4 narożniki prostokąta
            tableArea = [
                CGPoint(x: min(start.x, end.x), y: min(start.y, end.y)), // lewy górny
                CGPoint(x: max(start.x, end.x), y: min(start.y, end.y)), // prawy górny
                CGPoint(x: max(start.x, end.x), y: max(start.y, end.y)), // prawy dolny
                CGPoint(x: min(start.x, end.x), y: max(start.y, end.y))  // lewy dolny
            ]
        }
        
        // Wysyłamy oryginalne współrzędne łuz i obszaru stołu (na obrazku)
        // NetworkManager sam je przeskaluje
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
        isEditingTableArea = false
        dragHandle = nil
        dragStartPoint = nil
        cueBallColor = "White"
    }
    
    // Rysowanie linii najlepszego strzału
    @ViewBuilder
    func drawBestShot(result: BestShotResult, scale: CGFloat, offset: CGPoint) -> some View {
        let shot = result.best_shot
        
        // Linia Cel -> Łuza (Zielona)
        if let line1 = shot.shot_lines.first {
            let start = convertFromImageToView(point: line1.start, scale: scale, offset: offset)
            let end = convertFromImageToView(point: line1.end, scale: scale, offset: offset)
            Path { p in p.move(to: start); p.addLine(to: end) }
                .stroke(Color.green, lineWidth: 3)
        }
        
        // Linia Biała -> Duch (Biała przerywana)
        if shot.shot_lines.count > 1 {
            let line2 = shot.shot_lines[1]
            let start = convertFromImageToView(point: line2.start, scale: scale, offset: offset)
            let end = convertFromImageToView(point: line2.end, scale: scale, offset: offset)
            Path { p in p.move(to: start); p.addLine(to: end) }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, dash: [10]))
        }
        
        // Bila Duch (Kółko)
        let ghostCenter = convertFromImageToView(point: shot.ghost_ball.center, scale: scale, offset: offset)
        let r = CGFloat(shot.ghost_ball.radius) * scale
        Circle().stroke(Color.white, lineWidth: 2)
            .frame(width: r*2, height: r*2).position(ghostCenter)
            
        // Oznacz Białą (Niebieska kropka)
        let whiteCenter = convertFromImageToView(point: result.white_ball, scale: scale, offset: offset)
        Circle().fill(Color.blue).frame(width: 15, height: 15).position(whiteCenter)
        
        // Oznacz wybraną Bilę Cel (Czerwona kropka)
        let targetCenter = convertFromImageToView(point: shot.target_ball, scale: scale, offset: offset)
        Circle().fill(Color.red).frame(width: 15, height: 15).position(targetCenter)
    }
    
    // (Tutaj wklej swoje stare funkcje pomocnicze: calculateScaleAndOffset, convertFromViewToImage, convertFromImageToView)
    // One się nie zmieniły, więc możesz je skopiować ze starego pliku.
    
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
    
    // Potrzebne do konwersji Ball -> Point w funkcji drawBestShot
    func convertFromImageToView(point: Ball, scale: CGFloat, offset: CGPoint) -> CGPoint {
        let viewX = (CGFloat(point.x) * scale) + offset.x
        let viewY = (CGFloat(point.y) * scale) + offset.y
        return CGPoint(x: viewX, y: viewY)
    }
}