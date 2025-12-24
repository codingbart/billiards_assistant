import SwiftUI
import PhotosUI

// Style przycisków
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

// ImagePicker
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

// Pomocnicze funkcje UI
struct UIHelpers {
    static func colorForClass(_ cls: String) -> Color {
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
}

