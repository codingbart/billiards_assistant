import SwiftUI
import AVFoundation // Framework do obsługi audio i wideo

// To jest "most" między starym światem (UIKit) a nowym (SwiftUI)
struct CameraViewController: UIViewControllerRepresentable {
    
    // Ta funkcja tworzy "koordynatora", który będzie zarządzał sesją kamery
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // Ta funkcja tworzy kontroler widoku, który będzie wyświetlał podgląd
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .black
        
        // Uruchom sesję kamery (logika jest w Koordynatorze)
        context.coordinator.startSession()
        
        // Stwórz warstwę podglądu wideo
        let previewLayer = AVCaptureVideoPreviewLayer(session: context.coordinator.session)
        previewLayer.videoGravity = .resizeAspectFill // Wypełnij cały ekran
        previewLayer.frame = viewController.view.bounds
        
        // Dodaj podgląd do widoku
        viewController.view.layer.addSublayer(previewLayer)
        
        return viewController
    }
    
    // Ta funkcja jest wywoływana, gdy widok SwiftUI się aktualizuje (np. obrót ekranu)
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Upewnij się, że podgląd zawsze wypełnia ekran
        if let previewLayer = uiViewController.view.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiViewController.view.bounds
        }
    }
    
    // --- To jest nasz menedżer kamery ---
    class Coordinator: NSObject {
        var parent: CameraViewController
        var session = AVCaptureSession() // Sesja przechwytywania
        
        init(_ parent: CameraViewController) {
            self.parent = parent
        }
        
        func startSession() {
            // Uruchamiamy sesję w tle, aby nie blokować interfejsu
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                // Ustaw jakość sesji na "zdjęcie"
                self.session.sessionPreset = .photo
                
                var device: AVCaptureDevice?
                
                if let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back){
                    device = backCamera
                } else if let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front){
                    print("Nie znaleziono tylnej kamery, używam przedniej.")
                    device = frontCamera
                }
                
                guard let captureDevice = device else {
                    print("Nie znaleziono ŻADNEJ kamery")
                    return
                }
                
                do{
                    let input = try AVCaptureDeviceInput(device: captureDevice)
                    
                    if self.session.canAddInput(input){
                        self.session.addInput(input)
                    } else{
                        print("Nie można dodać wejścia do sesji")
                        return
                    }
                    
                    self.session.startRunning()
                    print("Sesja kamery uruchomiona")
                } catch{
                    print("Błąd podczas tworzenia wejścia kamery: \(error.localizedDescription)")
                }
                
                
                
            }
        }
    }
}
