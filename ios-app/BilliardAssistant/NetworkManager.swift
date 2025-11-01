import Foundation
import UIKit

// --- Te struktury muszą DOKŁADNIE pasować do JSONa z Twojego backendu ---
struct AnalysisResult: Codable {
    let ghost_ball: GhostBall
    let other_balls: [Ball]
    let shot_lines: [Line]
    let white_ball: Ball
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

// Musi być `Codable`, abyśmy mogli to zakodować do JSON
struct Point: Codable {
    let x: Int
    let y: Int
}

struct GhostBall: Codable {
    let center: Point
    let radius: Int
}

// Struktura, którą wyślemy w polu 'data'
struct RequestData: Codable {
    let target_ball: Point
    let pocket: Point
}
// --- Koniec struktur ---


class NetworkManager {
    
    // ---------------------------------------------------------------
    // ⚠️ WAŻNE: ZMIEŃ TO IP ⚠️
    // Wpisz tutaj adres IP swojego komputera w sieci lokalnej
    // (Na Macu: Ustawienia -> Wi-Fi -> (i) obok nazwy sieci -> Adres IP)
    // ---------------------------------------------------------------
    let serverURLString = "http://192.168.2.111:5001/analyze"
    
    
    // Ta funkcja jest teraz w pełni zaimplementowana!
    func analyzeImage(image: UIImage, targetBall: Point, pocket: Point, completion: @escaping (Result<AnalysisResult, Error>) -> Void) {
        
        print("Rozpoczynam analizę... cel: \(targetBall), łuza: \(pocket)")
        
        guard let serverURL = URL(string: serverURLString) else {
            completion(.failure(NSError(domain: "NetworkManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Nieprawidłowy adres URL serwera"])))
            return
        }
        
        // 1. Przygotuj dane JSON do wysłania
        let requestData = RequestData(target_ball: targetBall, pocket: pocket)
        guard let jsonData = try? JSONEncoder().encode(requestData) else {
            completion(.failure(NSError(domain: "NetworkManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Nie udało się zakodować danych do JSON"])))
            return
        }
        
        // 2. Przygotuj obraz
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(NSError(domain: "NetworkManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Nie udało się przekonwertować obrazu na JPEG"])))
            return
        }
        
        // 3. Stwórz żądanie 'multipart/form-data'
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // --- Część 1: Pole 'data' (JSON) ---
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"data\"\r\n\r\n".data(using: .utf8)!)
        body.append(jsonData)
        body.append("\r\n".data(using: .utf8)!)
        
        // --- Część 2: Pole 'file' (Obraz) ---
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpegData)
        body.append("\r\n".data(using: .utf8)!)
        
        // --- Zakończenie ---
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        // 4. Wyślij żądanie
        URLSession.shared.dataTask(with: request) { data, response, error in
            // Przełącz z powrotem na główny wątek, aby zaktualizować UI
            DispatchQueue.main.async {
                if let error = error {
                    print("BŁĄD SIECIOWY: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    print("BŁĄD SERWERA: \(response.debugDescription)")
                    completion(.failure(NSError(domain: "NetworkManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Błąd serwera (kod inny niż 2xx)"])))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "NetworkManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Brak danych w odpowiedzi"])))
                    return
                }
                
                // 5. Zdekoduj odpowiedź JSON
                do {
                    let analysisResult = try JSONDecoder().decode(AnalysisResult.self, from: data)
                    print("SUKCES: Otrzymano wynik analizy.")
                    completion(.success(analysisResult))
                } catch {
                    print("BŁĄD DEKODOWANIA JSON: \(error)")
                    // Spróbuj wydrukować, co serwer faktycznie odesłał
                    if let errorString = String(data: data, encoding: .utf8) {
                        print("Serwer zwrócił: \(errorString)")
                    }
                    completion(.failure(error))
                }
            }
        }.resume()
    }
}
