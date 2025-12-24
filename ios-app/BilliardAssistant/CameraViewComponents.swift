import SwiftUI

struct CameraViewComponents {
    // Widok aparatu
    static func cameraView(
        capturedImage: Binding<UIImage?>,
        coordinator: CameraViewController.Coordinator,
        isShowingImagePicker: Binding<Bool>
    ) -> some View {
        ZStack {
            CameraViewController(capturedImage: capturedImage, coordinator: coordinator)
                .edgesIgnoringSafeArea(.all)
            VStack {
                Spacer()
                
                Text("Zrób zdjęcie lub wybierz z galerii")
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(10)
                    .foregroundColor(.white)
                    .padding(.bottom, 20)
                
                HStack {
                    Button(action: { isShowingImagePicker.wrappedValue = true }) {
                        VStack { 
                            Image(systemName: "photo")
                            Text("Galeria").font(.caption) 
                        }
                        .foregroundColor(.white)
                        .frame(width: 70)
                    }
                    Spacer()
                    Button(action: { coordinator.capturePhoto() }) {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 70, height: 70)
                    }
                    Spacer()
                    Color.clear.frame(width: 70)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
        .sheet(isPresented: isShowingImagePicker) { ImagePicker(image: capturedImage) }
    }
    
    // Widok edytora
    static func editorView(
        capturedImage: UIImage?,
        currentStep: AppStep,
        tableCorners: [CGPoint],
        pockets: [CGPoint],
        calibrationPoint: CGPoint?,
        detectedBalls: Binding<[DetectedBall]>,
        bestShotResult: BestShotResult?,
        errorMessage: String?,
        availableColors: [String],
        onTap: @escaping (CGPoint, CGSize, CGSize) -> Void,
        bottomControlPanel: @escaping () -> some View
    ) -> some View {
        GeometryReader { geometry in
            let (scale, offset) = CoordinateHelpers.calculateScaleAndOffset(
                imageSize: capturedImage?.size ?? .zero,
                viewSize: geometry.size
            )
            
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
                                        onTap(val.startLocation, image.size, geometry.size)
                                    }
                                }
                        )
                        .disabled(currentStep == .result)
                    
                    // --- RYSOWANIE ---
                    
                    // 1. Stół i łuzy (Tylko w marking + verifying)
                    if currentStep != .result {
                        DrawingHelpers.drawTableAndPockets(
                            tableCorners: tableCorners,
                            pockets: pockets,
                            scale: scale,
                            offset: offset
                        )
                    }
                    
                    // Punkt kalibracji (tylko poza wynikiem)
                    if currentStep != .result, let cp = calibrationPoint {
                        let vp = CoordinateHelpers.convert(cp, scale, offset)
                        Image(systemName: "eyedropper")
                            .foregroundColor(.cyan)
                            .position(vp)
                    }
                    
                    // 2. Weryfikacja bil (tylko verifying)
                    if currentStep == .verifying {
                        DrawingHelpers.drawBallsForVerification(
                            detectedBalls: detectedBalls,
                            availableColors: availableColors,
                            scale: scale,
                            offset: offset
                        )
                    }
                    
                    // 3. Wynik (tylko w result)
                    if currentStep == .result, let res = bestShotResult {
                        DrawingHelpers.drawBestShot(
                            result: res,
                            scale: scale,
                            offset: offset
                        )
                    }
                }
                
                VStack {
                    if let err = errorMessage {
                        Text(err).foregroundColor(.white).padding().background(Color.red).cornerRadius(8).padding()
                    }
                    Spacer()
                    bottomControlPanel()
                }
            }
        }
    }
    
    // Panel dolny zależny od kroku
    static func bottomControlPanel(
        currentStep: AppStep,
        isCalibrating: Bool,
        tableCorners: [CGPoint],
        pockets: [CGPoint],
        isSelectingTableArea: Bool,
        cueBallColor: Binding<String>,
        availableColors: [String],
        isLoading: Bool,
        bestShotResult: BestShotResult?,
        onSetMode: @escaping (Bool) -> Void,
        onCalibrate: @escaping () -> Void,
        onReset: @escaping () -> Void,
        onRunDetection: @escaping () -> Void,
        onBack: @escaping () -> Void,
        onRunCalculation: @escaping () -> Void
    ) -> some View {
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
                        Button("Rogi (\(tableCorners.count))") { onSetMode(true) }
                            .buttonStyle(ModeBtn(active: isSelectingTableArea && !isCalibrating))
                        Button("Łuzy (\(pockets.count))") { onSetMode(false) }
                            .buttonStyle(ModeBtn(active: !isSelectingTableArea && !isCalibrating))
                        Button(action: onCalibrate) {
                            Image(systemName: "eyedropper")
                        }
                        .buttonStyle(ModeBtn(active: isCalibrating))
                    }
                    HStack {
                        Button("Reset") { onReset() }.foregroundColor(.red)
                        Spacer()
                        Button("DALEJ >") { onRunDetection() }
                            .buttonStyle(ActionBtn(enabled: tableCorners.count == 4 && !pockets.isEmpty))
                            .disabled(tableCorners.count != 4 || pockets.isEmpty || isLoading)
                    }
                }.padding().background(Color.black.opacity(0.8))
                
            case .verifying:
                VStack(spacing: 15) {
                    Text("2. Sprawdź kolory (kliknij w bilę)").font(.headline).foregroundColor(.white)
                    HStack {
                        Text("Twoja bila:")
                        Picker("", selection: cueBallColor) {
                            ForEach(availableColors.filter{$0 != "Ignore"}, id: \.self) { c in Text(c).tag(c) }
                        }.pickerStyle(.menu)
                    }.foregroundColor(.white)
                    
                    HStack {
                        Button("Wstecz") { onBack() }.foregroundColor(.white)
                        Spacer()
                        if isLoading { ProgressView().tint(.white) }
                        else {
                            Button("OBLICZ STRZAŁ") { onRunCalculation() }
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
                    
                    Button("Od nowa") { onReset() }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding(.bottom)
                }
            }
        }
    }
}

