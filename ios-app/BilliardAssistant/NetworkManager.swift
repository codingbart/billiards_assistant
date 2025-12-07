import Foundation
import UIKit

// --- Modele Danych ---

struct BestShotResult: Codable {
    let white_ball: Ball
    let other_balls: [Ball]
    let best_shot: BestShotDetail
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
    
    // Upewnij się, że IP jest poprawne!
    let serverURLString = "http://192.168.30.112:5001/analyze_best_shot"
    
    private let urlSession: URLSession
    
    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 180.0
        configuration.timeoutIntervalForResource = 180.0
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
        
        print("Wysyłam zdjęcie, \(pockets.count) łuz, kolor bili cue: \(cueBallColor)")
        if let area = tableArea {
            print("Obszar stołu: \(area.count) punktów")
        }
        
        guard let serverURL = URL(string: serverURLString) else {
            completion(.failure(NSError(domain: "Network", code: -1, userInfo: [NSLocalizedDescriptionKey: "Zły URL"])))
            return
        }
        
        // 1. Konwersja łuz (CGPoint -> Point)
        // Musimy przeskalować punkty łuz z ekranu na wymiary obrazka, który wysyłamy (416px)
        let targetWidth: CGFloat = 416.0
        
        // Skalujemy oryginalny obraz
        guard let resizedImage = image.resized(toWidth: targetWidth) else {
             completion(.failure(NSError(domain: "Network", code: -2, userInfo: [NSLocalizedDescriptionKey: "Błąd skalowania"])))
             return
        }
        
        // Obliczamy skalę dla punktów (jak bardzo zmniejszyliśmy obraz)
        let scaleFactor = targetWidth / image.size.width
        
        // Przeliczamy łuzy na współrzędne małego obrazka
        let pocketPoints = pockets.map { point in
            return Point(x: Int(point.x * scaleFactor), y: Int(point.y * scaleFactor))
        }
        
        // Przeliczamy obszar stołu na współrzędne małego obrazka (jeśli podano)
        var tableAreaPoints: [Point]? = nil
        if let area = tableArea {
            tableAreaPoints = area.map { point in
                return Point(x: Int(point.x * scaleFactor), y: Int(point.y * scaleFactor))
            }
        }
        
        // 2. Kodowanie łuz do JSON
        guard let pocketsData = try? JSONEncoder().encode(pocketPoints),
              let pocketsString = String(data: pocketsData, encoding: .utf8) else {
            completion(.failure(NSError(domain: "Network", code: -3, userInfo: [NSLocalizedDescriptionKey: "Błąd kodowania łuz"])))
            return
        }
        
        // 3. Przygotowanie Requestu (Multipart)
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        guard let jpegData = resizedImage.jpegData(compressionQuality: 0.7) else { return }
        
        var body = Data()
        
        // Dodaj pole 'pockets'
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"pockets\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(pocketsString)\r\n".data(using: .utf8)!)
        
        // Dodaj pole 'cue_ball_color'
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"cue_ball_color\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(cueBallColor)\r\n".data(using: .utf8)!)
        
        // Dodaj pole 'table_area' (jeśli podano)
        if let areaPoints = tableAreaPoints {
            if let areaData = try? JSONEncoder().encode(areaPoints),
               let areaString = String(data: areaData, encoding: .utf8) {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"table_area\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(areaString)\r\n".data(using: .utf8)!)
            }
        }
        
        // Dodaj plik
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpegData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        // 4. Wyślij
        urlSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else { return }
                
                // Debugowanie błędów serwera
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    let errorMsg = String(data: data, encoding: .utf8) ?? "Błąd serwera"
                    completion(.failure(NSError(domain: "Server", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])))
                    return
                }
                
                do {
                    let result = try JSONDecoder().decode(BestShotResult.self, from: data)
                    completion(.success(result))
                } catch {
                    print("JSON Error: \(error)")
                    completion(.failure(error))
                }
            }
        }.resume()
    }
}

// Helper w tym samym pliku
extension UIImage {
    func resized(toWidth width: CGFloat) -> UIImage? {
        let canvasSize = CGSize(width: width, height: CGFloat(ceil(width/size.width * size.height)))
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: imageRendererFormat)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: canvasSize))
        }
    }
}
