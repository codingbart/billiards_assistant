import Foundation
import UIKit

class NetworkManager {
    
    // TWOJE IP (Upewnij się, że jest poprawne)
    let baseURL = "http://192.168.30.112:5001"
    
    private let urlSession: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0
        self.urlSession = URLSession(configuration: config)
    }
    
    // KROK 1: Detekcja (Zwraca listę bil)
    func detectBalls(image: UIImage, tableArea: [CGPoint]?, completion: @escaping (Result<[DetectedBall], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/detect") else { return }
        
        let targetWidth: CGFloat = 640.0
        guard let (resizedImage, scaleFactor) = getNormalizedImage(image: image, targetWidth: targetWidth) else {
            completion(.failure(NSError(domain: "App", code: -1, userInfo: [NSLocalizedDescriptionKey: "Błąd obrazu"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Obszar stołu
        if let area = tableArea {
            let scaledArea = area.map { Point(x: Int($0.x * scaleFactor), y: Int($0.y * scaleFactor)) }
            if let areaData = try? JSONEncoder().encode(scaledArea), let areaStr = String(data: areaData, encoding: .utf8) {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"table_area\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(areaStr)\r\n".data(using: .utf8)!)
            }
        }
        
        // Plik
        if let jpeg = resizedImage.jpegData(compressionQuality: 0.8) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"img.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(jpeg)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        print("Wysyłam do detekcji...")
        
        urlSession.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { return }
                
                do {
                    let res = try JSONDecoder().decode(DetectionResponse.self, from: data)
                    // Skalowanie w górę (powrót do oryginału)
                    let upScale = 1.0 / scaleFactor
                    let finalBalls = res.balls.map { b in
                        var newB = b
                        newB.x = Int(CGFloat(b.x) * upScale)
                        newB.y = Int(CGFloat(b.y) * upScale)
                        newB.r = Int(CGFloat(b.r) * upScale)
                        return newB
                    }
                    completion(.success(finalBalls))
                } catch {
                    print("Błąd JSON Detect: \(error)")
                    if let s = String(data: data, encoding: .utf8) { print("Raw: \(s)") }
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    // KROK 2: Obliczenia (Wysyła poprawione bile)
    func calculateShot(balls: [DetectedBall], pockets: [CGPoint], tableArea: [CGPoint]?, cueBallColor: String, completion: @escaping (Result<BestShotResult, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/calculate") else { return }
        
        let ballsDicts = balls.map { ["x": $0.x, "y": $0.y, "r": $0.r, "class": $0.ballClass] }
        let pocketsDicts = pockets.map { ["x": Int($0.x), "y": Int($0.y)] }
        let areaDicts = tableArea?.map { ["x": Int($0.x), "y": Int($0.y)] } ?? []
        
        let payload: [String: Any] = [
            "balls": ballsDicts,
            "pockets": pocketsDicts,
            "table_area": areaDicts,
            "cue_ball_color": cueBallColor
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        print("Wysyłam do obliczeń...")
        
        urlSession.dataTask(with: request) { data, resp, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { return }
                
                if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode != 200 {
                    let msg = String(data: data, encoding: .utf8) ?? "Błąd serwera"
                    completion(.failure(NSError(domain: "Server", code: httpResp.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])))
                    return
                }
                
                do {
                    let res = try JSONDecoder().decode(CalculationResponse.self, from: data)
                    completion(.success(BestShotResult(best_shot: res.best_shot)))
                } catch {
                    print("Błąd JSON Calc: \(error)")
                    if let s = String(data: data, encoding: .utf8) { print("Raw: \(s)") }
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    private func getNormalizedImage(image: UIImage, targetWidth: CGFloat) -> (UIImage, CGFloat)? {
        let scaleFactor = targetWidth / image.size.width
        let targetHeight = image.size.height * scaleFactor
        let newSize = CGSize(width: targetWidth, height: targetHeight)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        guard let finalImage = newImage else { return nil }
        return (finalImage, scaleFactor)
    }
}
