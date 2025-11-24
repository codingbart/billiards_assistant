import SwiftUI
import AVFoundation
import Combine

struct CameraViewController: UIViewControllerRepresentable {
    
    @Binding var capturedImage: UIImage?
    
    var coordinator: Coordinator
    
    func makeCoordinator() -> Coordinator {
        return coordinator
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
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
    class Coordinator: NSObject, AVCapturePhotoCaptureDelegate, ObservableObject {
        
        var parent: CameraViewController?
        var session = AVCaptureSession()
        var previewLayer: AVCaptureVideoPreviewLayer?
        
        private var photoOutput = AVCapturePhotoOutput()
        
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
                self.parent?.capturedImage = image
                print("Zdjęcie zrobione i przekazane do CameraView")
            }
        }
    }
}
