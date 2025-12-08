import Foundation
import UIKit

// Struktury bez zmian...
struct BestShotResult: Codable {
    let white_ball: Ball
    let other_balls: [Ball]
    let best_shot: BestShotDetail
    let all_detected_balls: [DetectedBall]?  // Wszystkie wykryte bile (przed filtracją obszarem)
}

struct DetectedBall: Codable {
    let x: Int
    let y: Int
    let r: Int
    let ballClass: String
    let confidence: Double
    
    enum CodingKeys: String, CodingKey {
        case x, y, r, confidence
        case ballClass = "class"
    }
}

struct BestShotDetail: Codable {
    let target_ball: Ball
    let pocket: Point
    let angle: Double
    let shot_lines: [Line]
    let ghost_ball: GhostBall
}

struct Ball: Codable {
    let r: Int
    let x: Int
    let y: Int
}

struct Line: Codable {
    let start: Point
    let end: Point
}

struct Point: Codable {
    let x: Int
    let y: Int
}

struct GhostBall: Codable {
    let center: Point
    let radius: Int
}

class NetworkManager {
    
    // Zaktualizuj IP serwera jeśli się zmieni
    let serverURLString = "http://192.168.30.112:5001/analyze_best_shot"
    
    private let urlSession: URLSession
    
    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60.0 // Krótszy timeout, 180s to za długo
        self.urlSession = URLSession(configuration: configuration)
    }
    
    func analyzeBestShot(
        image: UIImage,
        pockets: [CGPoint],
        imageSize: CGSize,
        tableArea: [CGPoint]? = nil,
        cueBallColor: String = "White",
        completion: @escaping (Result<BestShotResult, Error>) -> Void
    ) {
        guard let serverURL = URL(string: serverURLString) else {
            completion(.failure(NSError(domain: "Network", code: -1, userInfo: [NSLocalizedDescriptionKey: "Nieprawidłowy URL"])))
            return
        }
        
        // 1. Skalowanie obrazu
        // Roboflow i tak przetwarza małe obrazy, więc zmniejszamy przed wysłaniem dla szybkości
        let targetWidth: CGFloat = 640.0 // Zwiększyłem z 416 na 640 dla lepszej detekcji przy zachowaniu szybkości
        
        // WAŻNE: Używamy rzeczywistego rozmiaru obrazu w pikselach, nie w punktach
        // image.size zwraca rozmiar w punktach, ale musimy użyć rozmiaru w pikselach
        let imagePixelWidth = image.size.width * image.scale
        let imagePixelHeight = image.size.height * image.scale
        
        guard let resizedImage = image.resized(toWidth: targetWidth) else {
             completion(.failure(NSError(domain: "Network", code: -2, userInfo: [NSLocalizedDescriptionKey: "Błąd skalowania obrazu"])))
             return
        }
        
        // WAŻNE: Sprawdzamy rzeczywisty rozmiar przeskalowanego obrazu
        // resizedImage może mieć inny rozmiar niż targetWidth z powodu zaokrągleń
        let actualResizedWidth = resizedImage.size.width * resizedImage.scale
        let actualResizedHeight = resizedImage.size.height * resizedImage.scale
        
        // Obliczamy skalę (jak bardzo zmniejszyliśmy oryginał)
        // Używamy rzeczywistego rozmiaru w pikselach, nie w punktach
        // Używamy rzeczywistego rozmiaru przeskalowanego obrazu, nie targetWidth
        let scaleFactor = actualResizedWidth / imagePixelWidth
        
        // Logowanie dla debugowania
        print("DEBUG: Oryginalny obraz: \(imagePixelWidth)x\(imagePixelHeight) pikseli")
        print("DEBUG: Przeskalowany obraz: \(actualResizedWidth)x\(actualResizedHeight) pikseli")
        print("DEBUG: Scale factor: \(scaleFactor)")
        
        // 2. Przeliczanie punktów
        // WAŻNE: pockets i tableArea są w przestrzeni obrazu w punktach, ale musimy je przeliczyć na piksele
        // przed skalowaniem, bo obraz jest skalowany w pikselach
        let imageScale = image.scale
        
        let pocketPoints = pockets.map { point in
            // Przelicz z punktów na piksele, potem skaluj
            let pixelX = point.x * imageScale
            let pixelY = point.y * imageScale
            return Point(x: Int(pixelX * scaleFactor), y: Int(pixelY * scaleFactor))
        }
        
        var tableAreaPoints: [Point]? = nil
        if let area = tableArea {
            print("DEBUG: Obszar stołu (punkty obrazu):")
            for (i, point) in area.enumerated() {
                print("  Punkt \(i+1): x=\(point.x), y=\(point.y)")
            }
            
            tableAreaPoints = area.map { point in
                // Przelicz z punktów na piksele, potem skaluj
                let pixelX = point.x * imageScale
                let pixelY = point.y * imageScale
                let scaledX = Int(pixelX * scaleFactor)
                let scaledY = Int(pixelY * scaleFactor)
                print("DEBUG: Przeliczenie: punkt(\(point.x), \(point.y)) -> piksel(\(pixelX), \(pixelY)) -> przeskalowany(\(scaledX), \(scaledY))")
                return Point(x: scaledX, y: scaledY)
            }
            
            print("DEBUG: Obszar stołu (przeskalowany):")
            for (i, point) in tableAreaPoints!.enumerated() {
                print("  Punkt \(i+1): x=\(point.x), y=\(point.y)")
            }
        }
        
        // 3. Budowanie Requestu
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        guard let jpegData = resizedImage.jpegData(compressionQuality: 0.8) else { return }
        
        var body = Data()
        
        // Pockets
        if let pocketsData = try? JSONEncoder().encode(pocketPoints),
           let pocketsString = String(data: pocketsData, encoding: .utf8) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"pockets\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(pocketsString)\r\n".data(using: .utf8)!)
        }
        
        // Cue Ball Color
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"cue_ball_color\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(cueBallColor)\r\n".data(using: .utf8)!)
        
        // Table Area
        if let areaPoints = tableAreaPoints {
            if let areaData = try? JSONEncoder().encode(areaPoints),
               let areaString = String(data: areaData, encoding: .utf8) {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"table_area\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(areaString)\r\n".data(using: .utf8)!)
            }
        }
        
        // File
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpegData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        // 4. Wysłanie
        urlSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "Network", code: -4, userInfo: [NSLocalizedDescriptionKey: "Brak danych z serwera"])))
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    let errorMsg = String(data: data, encoding: .utf8) ?? "Błąd serwera (kod \(httpResponse.statusCode))"
                    completion(.failure(NSError(domain: "Server", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])))
                    return
                }
                
                do {
                    let result = try JSONDecoder().decode(BestShotResult.self, from: data)
                    completion(.success(result))
                } catch {
                    print("Błąd dekodowania JSON: \(error)")
                    // Wypisz surowy JSON w konsoli dla debugowania
                    if let str = String(data: data, encoding: .utf8) {
                        print("Otrzymany JSON: \(str)")
                    }
                    completion(.failure(error))
                }
            }
        }.resume()
    }
}

extension UIImage {
    func resized(toWidth width: CGFloat) -> UIImage? {
        // Obliczamy nowy rozmiar
        let canvasSize = CGSize(width: width, height: CGFloat(ceil(width/size.width * size.height)))
        
        // KRYTYCZNA POPRAWKA:
        // Ustawiamy scale = 1, aby wymiary w pikselach były dokładnie takie jak canvasSize.
        // Bez tego na iPhone (Retina) obrazek byłby 2x lub 3x większy (w pikselach), 
        // co psuje obliczenia współrzędnych na serwerze.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 
        
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: canvasSize))
        }
    }
}
