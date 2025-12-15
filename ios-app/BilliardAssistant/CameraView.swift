import SwiftUI
import PhotosUI

struct CameraView: View {
    @State private var capturedImage: UIImage?
    @StateObject private var cameraCoordinator = CameraViewController.Coordinator()
    
    // Dane
    @State private var pockets: [CGPoint] = []
    @State private var tableCorners: [CGPoint] = []
    @State private var detectedBalls: [DetectedBall] = [] // Bile do edycji
    @State private var bestShotResult: BestShotResult?    // Wynik końcowy
    
    // Kalibracja
    @State private var isCalibrating = false
    @State private var calibrationPoint: CGPoint?
    
    // UI
    @State private var isSelectingTableArea = false
    @State private var isShowingImagePicker = false
    @State private var cueBallColor = "White"
    @State private var currentStep: AppStep = .marking // Faza aplikacji
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    let networkManager = NetworkManager()
    let availableColors = ["White", "Yellow", "Blue", "Red", "Purple", "Orange", "Green", "Brown", "Black", "Ignore"]
    
    enum AppStep {
        case marking    // 1. Zaznacz stół i łuzy
        case verifying  // 2. Popraw kolory bil
        case result     // 3. Wynik
    }
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if capturedImage == nil {
                // --- WIDOK APARATU ---
                cameraView
            } else {
                // --- WIDOK EDYCJI ---
                editorView
            }
        }
    }
    
    // Widok aparatu
    var cameraView: some View {
        ZStack {
            CameraViewController(capturedImage: $capturedImage, coordinator: cameraCoordinator)
                .edgesIgnoringSafeArea(.all)
            VStack {
                Spacer()
                Text("Zrób zdjęcie lub wybierz z galerii").padding().background(Color.black.opacity(0.6)).cornerRadius(10).foregroundColor(.white).padding(.bottom, 100)
                HStack {
                    Button(action: { isShowingImagePicker = true }) {
                        VStack { Image(systemName: "photo"); Text("Galeria").font(.caption) }.foregroundColor(.white).frame(width: 70)
                    }
                    Spacer()
                    Button(action: { cameraCoordinator.capturePhoto() }) {
                        Circle().stroke(Color.white, lineWidth: 4).frame(width: 70, height: 70)
                    }
                    Spacer()
                    Color.clear.frame(width: 70)
                }.padding(.bottom, 40).padding(.horizontal)
            }
        }
        .sheet(isPresented: $isShowingImagePicker) { ImagePicker(image: $capturedImage) }
    }
    
    // Widok edytora
    var editorView: some View {
        GeometryReader { geometry in
            let (scale, offset) = calculateScaleAndOffset(imageSize: capturedImage?.size ?? .zero, viewSize: geometry.size)
            
            ZStack {
                if let image = capturedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .position(x: geometry.size.width/2, y: geometry.size.height/2)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { val in
                                    if currentStep == .marking && abs(val.translation.width) < 5 {
                                        handleTap(at: val.startLocation, imageSize: image.size, viewSize: geometry.size)
                                    }
                                }
                        )
                        .disabled(currentStep == .result)  // WYŁĄCZA TAPPY W WYNIKU
                    
                    // --- RYSOWANIE ---
                    
                    // 1. Stół i łuzy (Tylko w marking + verifying)
                    if currentStep != .result {
                        drawTableAndPockets(scale: scale, offset: offset)
                    }
                    
                    // Punkt kalibracji (tylko poza wynikiem)
                    if currentStep != .result, let cp = calibrationPoint {
                        let vp = convert(cp, scale, offset)
                        Image(systemName: "eyedropper")
                            .foregroundColor(.cyan)
                            .position(vp)
                    }
                    
                    // 2. Weryfikacja bil (tylko verifying)
                    if currentStep == .verifying {
                        drawBallsForVerification(scale: scale, offset: offset)
                    }
                    
                    // 3. Wynik (tylko w result)
                    if currentStep == .result, let res = bestShotResult {
                        drawBestShot(result: res, scale: scale, offset: offset)
                    }
                }
                
                VStack {
                    if let err = errorMessage {
                        Text(err).foregroundColor(.white).padding().background(Color.red).cornerRadius(8).padding()
                    }
                    Spacer()
                    bottomControlPanel
                }
            }
        }
    }
    
    // Panel dolny zależny od kroku
    var bottomControlPanel: some View {
        Group {
            switch currentStep {
            case .marking:
                VStack(spacing: 15) {
                    if isCalibrating {
                        Text("Kliknij na tło (sukno)").foregroundColor(.cyan).bold()
                    } else {
                        Text("1. Zaznacz stół, łuzy i tło").foregroundColor(.white)
                    }
                    
                    HStack {
                        Button("Rogi (\(tableCorners.count))") { setMode(table: true) }
                            .buttonStyle(ModeBtn(active: isSelectingTableArea && !isCalibrating))
                        Button("Łuzy (\(pockets.count))") { setMode(table: false) }
                            .buttonStyle(ModeBtn(active: !isSelectingTableArea && !isCalibrating))
                        Button(action: { isCalibrating = true; isSelectingTableArea = false }) {
                            Image(systemName: "eyedropper")
                        }
                        .buttonStyle(ModeBtn(active: isCalibrating))
                    }
                    HStack {
                        Button("Reset") { resetAll() }.foregroundColor(.red)
                        Spacer()
                        Button("DALEJ >") { runDetection() }
                            .buttonStyle(ActionBtn(enabled: tableCorners.count == 4 && !pockets.isEmpty))
                            .disabled(tableCorners.count != 4 || pockets.isEmpty || isLoading)
                    }
                }.padding().background(Color.black.opacity(0.8))
                
            case .verifying:
                VStack(spacing: 15) {
                    Text("2. Sprawdź kolory (kliknij w bilę)").font(.headline).foregroundColor(.white)
                    HStack {
                        Text("Twoja bila:")
                        Picker("", selection: $cueBallColor) {
                            ForEach(availableColors.filter{$0 != "Ignore"}, id: \.self) { c in Text(c).tag(c) }
                        }.pickerStyle(.menu)
                    }.foregroundColor(.white)
                    
                    HStack {
                        Button("Wstecz") { currentStep = .marking }.foregroundColor(.white)
                        Spacer()
                        if isLoading { ProgressView().tint(.white) }
                        else {
                            Button("OBLICZ STRZAŁ") { runCalculation() }
                                .buttonStyle(ActionBtn(enabled: true))
                        }
                    }
                }.padding().background(Color.black.opacity(0.8))
                
            case .result:
                VStack {
                    if let angle = bestShotResult?.best_shot.angle {
                        Text("Kąt cięcia: \(String(format: "%.1f", angle))°")
                            .font(.title)
                            .bold()
                            .foregroundColor(.green)
                            .padding()
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(10)
                    }
                    
                    Spacer()
                    
                    Button("Od nowa") { resetAll() }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding(.bottom)
                }
            }
        }
    }
    
    // --- LOGIKA ---
    func setMode(table: Bool) {
        isSelectingTableArea = table
        isCalibrating = false
    }
    
    func runDetection() {
        guard let img = capturedImage else { return }
        isLoading = true; errorMessage = nil
        networkManager.detectBalls(image: img, tableArea: tableCorners, calibrationPoint: calibrationPoint) { res in
            isLoading = false
            switch res {
            case .success(let balls):
                self.detectedBalls = balls
                if balls.isEmpty { self.errorMessage = "Nie wykryto bil. Spróbuj skalibrować tło." }
                else { self.currentStep = .verifying }
            case .failure(let err): self.errorMessage = "Błąd: \(err.localizedDescription)"
            }
        }
    }
    
    func runCalculation() {
        isLoading = true; errorMessage = nil
        networkManager.calculateShot(balls: detectedBalls, pockets: pockets, tableArea: tableCorners, cueBallColor: cueBallColor) { res in
            isLoading = false
            switch res {
            case .success(let result):
                self.bestShotResult = result
                self.currentStep = .result
            case .failure(let err): self.errorMessage = "Błąd: \(err.localizedDescription)"
            }
        }
    }
    
    func handleTap(at location: CGPoint, imageSize: CGSize, viewSize: CGSize) {
        guard let p = convertFromViewToImage(point: location, imageSize: imageSize, viewSize: viewSize) else { return }
        let point = CGPoint(x: p.x, y: p.y)
        
        if isCalibrating {
            calibrationPoint = point
            isCalibrating = false
        } else if isSelectingTableArea {
            if tableCorners.count < 4 { tableCorners.append(point) }
            else { tableCorners = [point] }
        } else {
            pockets.append(point)
        }
    }
    
    func cycleColor(for ball: inout DetectedBall) {
        if let idx = availableColors.firstIndex(of: ball.ballClass.capitalized) {
            ball.ballClass = availableColors[(idx + 1) % availableColors.count]
        } else { ball.ballClass = "White" }
    }
    
    func resetAll() {
        capturedImage = nil
        pockets = []
        tableCorners = []
        detectedBalls = []
        bestShotResult = nil
        calibrationPoint = nil
        isCalibrating = false
        currentStep = .marking
        errorMessage = nil
    }
    
    // --- RYSOWANIE ---
    func drawTableAndPockets(scale: CGFloat, offset: CGPoint) -> some View {
        Group {
            if !tableCorners.isEmpty {
                Path { path in
                    for (i, p) in tableCorners.enumerated() {
                        let vp = convert(p, scale, offset)
                        i == 0 ? path.move(to: vp) : path.addLine(to: vp)
                    }
                    if tableCorners.count == 4 { path.closeSubpath() }
                }.stroke(Color.yellow, lineWidth: 2)
            }
            
            ForEach(pockets.indices, id: \.self) { i in
                Circle()
                    .fill(Color.green)
                    .frame(width: 20, height: 20)
                    .position(convert(pockets[i], scale, offset))
            }
        }
    }
    
    func drawBallsForVerification(scale: CGFloat, offset: CGPoint) -> some View {
        ForEach($detectedBalls) { $ball in
            let center = convert(CGPoint(x: ball.x, y: ball.y), scale, offset)
            let r = CGFloat(ball.r) * scale
            
            Button(action: { cycleColor(for: &ball) }) {
                ZStack {
                    if ball.ballClass == "Ignore" {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                    } else {
                        Circle().stroke(colorForClass(ball.ballClass), lineWidth: 3)
                            .background(Circle().fill(colorForClass(ball.ballClass).opacity(0.3)))
                            .frame(width: max(24, r*2), height: max(24, r*2))
                        Text(ball.ballClass.prefix(1).uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(radius: 1)
                    }
                }
            }
            .position(center)
        }
    }
    
    @ViewBuilder
    func drawBestShot(result: BestShotResult, scale: CGFloat, offset: CGPoint) -> some View {
        let shot = result.best_shot
        
        // Główna linia (zielona)
        if let l1 = shot.shot_lines.first {
            let s = convert(CGPoint(x: l1.start.x, y: l1.start.y), scale, offset)
            let e = convert(CGPoint(x: l1.end.x, y: l1.end.y), scale, offset)
            Path { p in p.move(to: s); p.addLine(to: e) }.stroke(Color.green, lineWidth: 4)
        }
        
        // Linia pomocnicza (biała przerywana)
        if shot.shot_lines.count > 1 {
            let l2 = shot.shot_lines[1]
            let s = convert(CGPoint(x: l2.start.x, y: l2.start.y), scale, offset)
            let e = convert(CGPoint(x: l2.end.x, y: l2.end.y), scale, offset)
            Path { p in p.move(to: s); p.addLine(to: e) }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, dash: [5]))
        }
        
        // Ghost ball
        let ghost = convert(CGPoint(x: shot.ghost_ball.center.x, y: shot.ghost_ball.center.y), scale, offset)
        let r = CGFloat(shot.ghost_ball.radius) * scale
        Circle().stroke(Color.white, lineWidth: 2)
            .frame(width: r * 2, height: r * 2)
            .position(ghost)
        
        // Target ball (czerwony punkt)
        let target = convert(CGPoint(x: shot.target_ball.x, y: shot.target_ball.y), scale, offset)
        Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)
            .position(target)
    }
    
    // --- POMOCNICY ---
    func colorForClass(_ cls: String) -> Color {
        switch cls.capitalized {
        case "White": return .white
        case "Yellow": return .yellow
        case "Blue": return .blue
        case "Red": return .red
        case "Purple": return .purple
        case "Orange": return .orange
        case "Green": return .green
        case "Brown": return .brown
        case "Black": return .gray
        default: return .white
        }
    }
    
    func calculateScaleAndOffset(imageSize: CGSize, viewSize: CGSize) -> (scale: CGFloat, offset: CGPoint) {
        guard imageSize.width > 0 else { return (0, .zero) }
        let widthScale = viewSize.width / imageSize.width
        let heightScale = viewSize.height / imageSize.height
        let scale = min(widthScale, heightScale)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return (scale, CGPoint(x: (viewSize.width - scaledSize.width)/2, y: (viewSize.height - scaledSize.height)/2))
    }
    
    func convertFromViewToImage(point: CGPoint, imageSize: CGSize, viewSize: CGSize) -> Point? {
        let (scale, offset) = calculateScaleAndOffset(imageSize: imageSize, viewSize: viewSize)
        return Point(x: Int((point.x - offset.x) / scale), y: Int((point.y - offset.y) / scale))
    }
    
    func convert(_ p: CGPoint, _ scale: CGFloat, _ offset: CGPoint) -> CGPoint {
        return CGPoint(x: p.x * scale + offset.x, y: p.y * scale + offset.y)
    }
}

// Komponenty UI
struct ModeBtn: ButtonStyle {
    var active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(8)
            .background(active ? Color.yellow : Color.gray.opacity(0.3))
            .foregroundColor(active ? .black : .white)
            .cornerRadius(8)
    }
}
struct ActionBtn: ButtonStyle {
    var enabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(enabled ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(10)
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) var presentationMode
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.presentationMode.wrappedValue.dismiss()
            guard let provider = results.first?.itemProvider else { return }
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { img, _ in
                    DispatchQueue.main.async {
                        self.parent.image = img as? UIImage
                    }
                }
            }
        }
    }
}
