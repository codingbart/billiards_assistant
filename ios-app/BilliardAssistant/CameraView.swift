import SwiftUI
import PhotosUI

struct CameraView: View {
    @State private var capturedImage: UIImage?
    @StateObject private var cameraCoordinator = CameraViewController.Coordinator()
    
    @State private var pockets: [CGPoint] = []
    @State private var tableCorners: [CGPoint] = []
    @State private var detectedBalls: [DetectedBall] = []
    @State private var bestShotResult: BestShotResult?
    
    @State private var isSelectingTableArea = false
    @State private var isShowingImagePicker = false
    @State private var cueBallColor = "White"
    @State private var currentStep: AppStep = .marking
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    let networkManager = NetworkManager()
    let availableColors = ["White", "Yellow", "Blue", "Red", "Purple", "Orange", "Green", "Brown", "Black", "Ignore"]
    
    enum AppStep {
        case marking, verifying, result
    }
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if capturedImage == nil {
                cameraView
            } else {
                editorView
            }
        }
    }
    
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
    
    var editorView: some View {
        GeometryReader { geometry in
            let (scale, offset) = calculateScaleAndOffset(imageSize: capturedImage?.size ?? .zero, viewSize: geometry.size)
            
            ZStack {
                if let image = capturedImage {
                    Image(uiImage: image).resizable().scaledToFit()
                        .position(x: geometry.size.width/2, y: geometry.size.height/2)
                        .gesture(DragGesture(minimumDistance: 0).onEnded { val in
                            if currentStep == .marking && abs(val.translation.width) < 5 {
                                handleTap(at: val.startLocation, imageSize: image.size, viewSize: geometry.size)
                            }
                        })
                    
                    // RYSOWANIE
                    drawTableAndPockets(scale: scale, offset: offset)
                    
                    if currentStep == .verifying {
                        drawBallsForVerification(scale: scale, offset: offset)
                    }
                    
                    if currentStep == .result, let res = bestShotResult {
                        drawBestShot(result: res, scale: scale, offset: offset)
                    }
                }
                
                // PANEL DOLNY
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
    
    // --- KOMPONENTY UI ---
    
    var bottomControlPanel: some View {
        Group {
            switch currentStep {
            case .marking:
                VStack(spacing: 15) {
                    Text("1. Zaznacz 4 rogi stołu i 6 łuz").font(.headline).foregroundColor(.white)
                    HStack {
                        Button("Rogi (\(tableCorners.count))") { isSelectingTableArea = true }
                            .buttonStyle(ModeBtn(active: isSelectingTableArea))
                        Button("Łuzy (\(pockets.count))") { isSelectingTableArea = false }
                            .buttonStyle(ModeBtn(active: !isSelectingTableArea))
                    }
                    HStack {
                        Button("Reset") { resetAll() }.foregroundColor(.red)
                        Spacer()
                        Button("DALEJ >") { runDetection() }
                            .buttonStyle(ActionBtn(enabled: tableCorners.count == 4))
                            .disabled(tableCorners.count != 4 || isLoading)
                    }
                }.padding().background(Color.black.opacity(0.8))
                
            case .verifying:
                VStack(spacing: 15) {
                    Text("2. Kliknij w bilę, by zmienić kolor").font(.headline).foregroundColor(.white)
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
                        Text("Kąt: \(String(format: "%.1f", angle))°")
                            .font(.title).bold().foregroundColor(.green)
                            .padding().background(Color.black.opacity(0.8)).cornerRadius(10)
                    }
                    Spacer()
                    Button("Od nowa") { resetAll() }
                        .padding().background(Color.blue).foregroundColor(.white).cornerRadius(10).padding(.bottom)
                }
            }
        }
    }
    
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
                Circle().fill(Color.green).frame(width: 20, height: 20).position(convert(pockets[i], scale, offset))
            }
        }
    }
    
    func drawBallsForVerification(scale: CGFloat, offset: CGPoint) -> some View {
        ForEach($detectedBalls) { $ball in
            let center = convert(CGPoint(x: ball.x, y: ball.y), scale, offset)
            let r = CGFloat(ball.r) * scale
            Button(action: { cycleColor(for: &ball) }) {
                ZStack {
                    if ball.ballClass == "ignore" {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                    } else {
                        Circle().stroke(colorForClass(ball.ballClass), lineWidth: 3)
                            .background(Circle().fill(colorForClass(ball.ballClass).opacity(0.3)))
                            .frame(width: max(20, r*2), height: max(20, r*2))
                        Text(ball.ballClass.prefix(1).uppercased())
                            .font(.system(size: 10, weight: .bold)).foregroundColor(.white).shadow(radius: 1)
                    }
                }
            }.position(center)
        }
    }
    
    @ViewBuilder
    func drawBestShot(result: BestShotResult, scale: CGFloat, offset: CGPoint) -> some View {
        let shot = result.best_shot
        if let l1 = shot.shot_lines.first {
            let s = convert(CGPoint(x: l1.start.x, y: l1.start.y), scale, offset)
            let e = convert(CGPoint(x: l1.end.x, y: l1.end.y), scale, offset)
            Path { p in p.move(to: s); p.addLine(to: e) }.stroke(Color.green, lineWidth: 4)
        }
        if shot.shot_lines.count > 1 {
            let l2 = shot.shot_lines[1]
            let s = convert(CGPoint(x: l2.start.x, y: l2.start.y), scale, offset)
            let e = convert(CGPoint(x: l2.end.x, y: l2.end.y), scale, offset)
            Path { p in p.move(to: s); p.addLine(to: e) }.stroke(Color.white, style: StrokeStyle(lineWidth: 3, dash: [5]))
        }
        let ghost = convert(CGPoint(x: shot.ghost_ball.center.x, y: shot.ghost_ball.center.y), scale, offset)
        let r = CGFloat(shot.ghost_ball.radius) * scale
        Circle().stroke(Color.white, lineWidth: 2).frame(width: r*2, height: r*2).position(ghost)
        
        let target = convert(CGPoint(x: shot.target_ball.x, y: shot.target_ball.y), scale, offset)
        Circle().fill(Color.red).frame(width: 10, height: 10).position(target)
    }
    
    // --- LOGIKA ---
    
    func runDetection() {
        guard let img = capturedImage else { return }
        isLoading = true; errorMessage = nil
        networkManager.detectBalls(image: img, tableArea: tableCorners) { res in
            isLoading = false
            switch res {
            case .success(let balls):
                self.detectedBalls = balls
                if balls.isEmpty { self.errorMessage = "Nie wykryto żadnych bil." }
                else { self.currentStep = .verifying }
            case .failure(let err): self.errorMessage = "Błąd: \(err.localizedDescription)"
            }
        }
    }
    
    func runCalculation() {
        guard let img = capturedImage else { return }
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
        if isSelectingTableArea {
            if tableCorners.count < 4 { tableCorners.append(point) }
            else { tableCorners = [point] }
        } else { pockets.append(point) }
    }
    
    func cycleColor(for ball: inout DetectedBall) {
        let colors = ["white", "yellow", "blue", "red", "purple", "orange", "green", "brown", "black", "ignore"]
        if let idx = colors.firstIndex(of: ball.ballClass.lowercased()) {
            ball.ballClass = colors[(idx + 1) % colors.count]
        } else { ball.ballClass = "white" }
    }
    
    func colorForClass(_ cls: String) -> Color {
        switch cls.lowercased() {
        case "white": return .white; case "yellow": return .yellow; case "blue": return .blue
        case "red": return .red; case "purple": return .purple; case "orange": return .orange
        case "green": return .green; case "brown": return .brown; case "black": return .gray
        default: return .white
        }
    }
    
    func resetAll() {
        capturedImage = nil; pockets = []; tableCorners = []; detectedBalls = []; bestShotResult = nil
        currentStep = .marking; errorMessage = nil
    }
    
    // --- SKALOWANIE ---
    
    func calculateScaleAndOffset(imageSize: CGSize, viewSize: CGSize) -> (scale: CGFloat, offset: CGPoint) {
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

// Komponent ImagePicker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) var presentationMode
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(); config.filter = .images
        let picker = PHPickerViewController(configuration: config); picker.delegate = context.coordinator; return picker
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
                provider.loadObject(ofClass: UIImage.self) { img, _ in DispatchQueue.main.async { self.parent.image = img as? UIImage } }
            }
        }
    }
}

// Style
struct ModeBtn: ButtonStyle {
    var active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(8).background(active ? Color.yellow : Color.gray.opacity(0.3))
            .foregroundColor(active ? .black : .white).cornerRadius(8)
    }
}
struct ActionBtn: ButtonStyle {
    var enabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding().background(enabled ? Color.blue : Color.gray)
            .foregroundColor(.white).cornerRadius(10)
    }
}
