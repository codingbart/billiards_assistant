import SwiftUI

struct CameraView: View {
    @State var capturedImage: UIImage?
    @StateObject private var cameraCoordinator = CameraViewController.Coordinator()
    
    // Dane
    @State var pockets: [CGPoint] = []
    @State var tableCorners: [CGPoint] = []
    @State var detectedBalls: [DetectedBall] = [] // Bile do edycji
    @State var bestShotResult: BestShotResult?    // Wynik końcowy
    
    // Kalibracja
    @State var isCalibrating = false
    @State var calibrationPoint: CGPoint?
    
    // UI
    @State var isSelectingTableArea = false
    @State var isShowingImagePicker = false
    @State var cueBallColor = "White"
    @State var currentStep: AppStep = .marking // Faza aplikacji
    @State var isLoading = false
    @State var errorMessage: String?
    
    let networkManager = NetworkManager()
    let availableColors = ["White", "Yellow", "Blue", "Red", "Purple", "Orange", "Green", "Brown", "Black", "Ignore"]
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if capturedImage == nil {
                // --- WIDOK APARATU ---
                CameraViewComponents.cameraView(
                    capturedImage: $capturedImage,
                    coordinator: cameraCoordinator,
                    isShowingImagePicker: $isShowingImagePicker
                )
            } else {
                // --- WIDOK EDYCJI ---
                CameraViewComponents.editorView(
                    capturedImage: capturedImage,
                    currentStep: currentStep,
                    tableCorners: tableCorners,
                    pockets: pockets,
                    calibrationPoint: calibrationPoint,
                    detectedBalls: $detectedBalls,
                    bestShotResult: bestShotResult,
                    errorMessage: errorMessage,
                    availableColors: availableColors,
                    onTap: { location, imageSize, viewSize in
                        handleTap(at: location, imageSize: imageSize, viewSize: viewSize)
                    },
                    bottomControlPanel: {
                        bottomControlPanel
                    }
                )
            }
        }
    }
    
    // Panel dolny zależny od kroku
    var bottomControlPanel: some View {
        CameraViewComponents.bottomControlPanel(
            currentStep: currentStep,
            isCalibrating: isCalibrating,
            tableCorners: tableCorners,
            pockets: pockets,
            isSelectingTableArea: isSelectingTableArea,
            cueBallColor: $cueBallColor,
            availableColors: availableColors,
            isLoading: isLoading,
            bestShotResult: bestShotResult,
            onSetMode: { table in setMode(table: table) },
            onCalibrate: { isCalibrating = true; isSelectingTableArea = false },
            onReset: { resetAll() },
            onRunDetection: { runDetection() },
            onBack: { currentStep = .marking },
            onRunCalculation: { runCalculation() }
        )
    }
}

// Enum dla faz aplikacji
enum AppStep {
    case marking    // 1. Zaznacz stół i łuzy
    case verifying  // 2. Popraw kolory bil
    case result     // 3. Wynik
}
