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
// Struktura dla trybu ręcznego (3 punkty)
struct RequestDataManual: Codable {
    let white_ball: Point
    let target_ball: Point
    let pocket: Point
}
// --- Koniec struktur ---


class NetworkManager {
    
    // ---------------------------------------------------------------
    // ⚠️ WAŻNE: ZMIEŃ TO IP ⚠️
    // ---------------------------------------------------------------
    let serverURLString = "http://192.168.2.111:5001/analyze"
    
    private let urlSession: URLSession
        
    init() {
        let configuration = URLSessionConfiguration.default
        // Ustaw limit czasu na 90 sekund (zamiast domyślnych 30-60)
        configuration.timeoutIntervalForRequest = 360.0
        configuration.timeoutIntervalForResource = 360.0
            
        self.urlSession = URLSession(configuration: configuration)
    }
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
        let targetWidth: CGFloat = 416.0
        var imageToProcess = image
                
        if image.size.width > targetWidth {
            print("Obraz jest za duży (\(image.size.width)px). Zmniejszam do \(targetWidth)px szerokości.")
            if let resizedImage = image.resized(toWidth: targetWidth) {
                imageToProcess = resizedImage
                print("Pomyślnie zmniejszono obraz do: \(imageToProcess.size)")
            } else {
                print("Nie udało się zmniejszyć obrazu, wysyłam oryginał.")
            }
        }

        guard let jpegData = imageToProcess.jpegData(compressionQuality: 0.7) else {
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
        urlSession.dataTask(with: request) { data, response, error in
            // Przełącz z powrotem na główny wątek, aby zaktualizować UI
            DispatchQueue.main.async {
                if let error = error {
                    print("BŁĄD SIECIOWY: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    print("BŁĄD SERWERA: \(response.debugDescription)")
                    if let data = data, let errorString = String(data: data, encoding: .utf8) {
                        print("Odpowiedź serwera: \(errorString)")
                        completion(.failure(NSError(domain: "NetworkManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Błąd serwera: \(errorString)"])))
                    } else {
                        completion(.failure(NSError(domain: "NetworkManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Błąd serwera (kod inny niż 2xx)"])))
                    }
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
                        print("Serwer zwrócił (błąd dekodowania): \(errorString)")
                    }
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    // === DODAJ CAŁĄ TĘ NOWĄ FUNKCJĘ ===

    func calculateManual(whiteBall: Point, targetBall: Point, pocket: Point, completion: @escaping (Result<AnalysisResult, Error>) -> Void) {

        print("Rozpoczynam analizę RĘCZNĄ... biała: \(whiteBall), cel: \(targetBall), łuza: \(pocket)")

        // Używamy nowego adresu URL
        guard let serverURL = URL(string: serverURLString.replacingOccurrences(of: "/analyze", with: "/calculate_manual")) else {
            completion(.failure(NSError(domain: "NetworkManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Nieprawidłowy adres URL serwera (/calculate_manual)"])))
            return
        }

        // 1. Przygotuj dane JSON (3 punkty)
        let requestData = RequestDataManual(white_ball: whiteBall, target_ball: targetBall, pocket: pocket)
        guard let jsonData = try? JSONEncoder().encode(requestData) else {
            completion(.failure(NSError(domain: "NetworkManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Nie udało się zakodować danych do JSON"])))
            return
        }

        // 2. Stwórz proste żądanie JSON (bez obrazu)
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        // 3. Wyślij żądanie (użyj naszej sesji z limitem czasu)
        urlSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("BŁĄD SIECIOWY (RĘCZNY): \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    print("BŁĄD SERWERA (RĘCZNY): \(response.debugDescription)")
                    if let data = data, let errorString = String(data: data, encoding: .utf8) {
                        print("Odpowiedź serwera: \(errorString)")
                        completion(.failure(NSError(domain: "NetworkManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Błąd serwera: \(errorString)"])))
                    } else {
                        completion(.failure(NSError(domain: "NetworkManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Błąd serwera (kod inny niż 2xx)"])))
                    }
                    return
                }

                guard let data = data else {
                    completion(.failure(NSError(domain: "NetworkManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Brak danych w odpowiedzi"])))
                    return
                }

                // 5. Zdekoduj odpowiedź JSON (używamy tej samej struktury AnalysisResult)
                do {
                    let analysisResult = try JSONDecoder().decode(AnalysisResult.self, from: data)
                    print("SUKCES (RĘCZNY): Otrzymano wynik analizy.")
                    completion(.success(analysisResult))
                } catch {
                    print("BŁĄD DEKODOWANIA JSON (RĘCZNY): \(error)")
                    if let errorString = String(data: data, encoding: .utf8) {
                        print("Serwer zwrócił (błąd dekodowania): \(errorString)")
                    }
                    completion(.failure(error))
                }
            }
        }.resume()
    }
}

// MARK: - Rozszerzenie do skalowania obrazów
extension UIImage {
    /// Zwraca obraz przeskalowany do nowej szerokości, zachowując proporcje.
    func resized(toWidth width: CGFloat) -> UIImage? {
        // Oblicz nową wysokość zachowując proporcje
        let canvasSize = CGSize(width: width, height: CGFloat(ceil(width/size.width * size.height)))
        
        // Użyj UIGraphicsImageRenderer (nowoczesny sposób)
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: imageRendererFormat)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: canvasSize))
        }
    }
}

