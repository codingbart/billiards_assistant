import SwiftUI
import AVFoundation
import Combine

struct CameraViewController: UIViewControllerRepresentable {
    
    @Binding var capturedImage: UIImage?
    
    // 1. Będziemy przekazywać Koordynatora z CameraView
    var coordinator: Coordinator
    
    // 2. Ta funkcja teraz po prostu zwraca przekazanego Koordynatora
    func makeCoordinator() -> Coordinator {
        return coordinator
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        // 3. Ustawiamy "rodzica" Koordynatora (czyli ten struct)
        context.coordinator.parent = self
        
        let viewController = UIViewController()
        viewController.view.backgroundColor = .black
        
        context.coordinator.setupSession()
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: context.coordinator.session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = viewController.view.bounds
        
        viewController.view.layer.addSublayer(previewLayer)
        
        DispatchQueue.global(qos: .userInitiated).async {
            context.coordinator.session.startRunning()
        }
        
        context.coordinator.previewLayer = previewLayer
        
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.previewLayer?.frame = uiViewController.view.bounds
    }
    
    // --- Koordynator (Menedżer Kamery) ---
    // Musi być teraz oddzielną klasą, aby @StateObject mógł ją stworzyć
    class Coordinator: NSObject, AVCapturePhotoCaptureDelegate, ObservableObject {
        
        // 4. 'parent' jest teraz opcjonalny, bo ustawiamy go później
        var parent: CameraViewController?
        var session = AVCaptureSession()
        var previewLayer: AVCaptureVideoPreviewLayer?
        
        private var photoOutput = AVCapturePhotoOutput()
        
        // 5. Publiczny init, aby @StateObject mógł go stworzyć
        public override init() {
            super.init()
        }
        
        func setupSession() {
            session.sessionPreset = .photo
            
            guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("Nie znaleziono tylnej kamery")
                return
            }
            
            do {
                let input = try AVCaptureDeviceInput(device: captureDevice)
                if session.canAddInput(input) {
                    session.addInput(input)
                } else {
                    print("Nie można dodać wejścia kamery do sesji")
                    return
                }
                
                if session.canAddOutput(photoOutput) {
                    session.addOutput(photoOutput)
                } else {
                    print("Nie można dodać wyjścia zdjęcia do sesji")
                    return
                }
                
            } catch {
                print("Błąd podczas tworzenia wejścia kamery: \(error.localizedDescription)")
            }
        }
        
        func capturePhoto() {
            print("Rozpoczynam robienie zdjęcia...")
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
        
        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            if let error = error {
                print("Błąd podczas robienia zdjęcia: \(error.localizedDescription)")
                return
            }
            
            guard let imageData = photo.fileDataRepresentation() else {
                print("Nie można pobrać danych zdjęcia")
                return
            }
            
            guard let image = UIImage(data: imageData) else {
                print("Nie można utworzyć UIImage z danych")
                return
            }
            
            DispatchQueue.main.async {
                // 6. Używamy 'parent?', bo jest opcjonalny
                self.parent?.capturedImage = image
                print("Zdjęcie zrobione i przekazane do CameraView")
            }
        }
    }
}
