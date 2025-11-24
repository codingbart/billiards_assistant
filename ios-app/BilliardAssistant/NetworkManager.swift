import Foundation
import UIKit

// MARK: - Konfiguracja
struct NetworkConfig {
    // Adres serwera - można zmienić w Info.plist lub przez zmienną środowiskową
    static var serverBaseURL: String {
        if let url = Bundle.main.object(forInfoDictionaryKey: "ServerBaseURL") as? String, !url.isEmpty {
            return url
        }
        // Domyślny adres (można zmienić w Info.plist)
        return "http://192.168.30.103:5001"
    }
    
    // Timeouty
    static let aiRequestTimeout: TimeInterval = 60.0  // 60s dla żądań AI
    static let manualRequestTimeout: TimeInterval = 10.0  // 10s dla żądań ręcznych
    
    // Parametry obrazu
    static let targetImageWidth: CGFloat = 416.0
    static let imageCompressionQuality: CGFloat = 0.7
    static let maxImageSize: Int = 10 * 1024 * 1024  // 10MB
    
    // Retry
    static let maxRetryAttempts = 2
    static let retryDelay: TimeInterval = 1.0
}

// MARK: - Typy błędów
enum NetworkError: LocalizedError {
    case invalidURL
    case encodingError
    case imageConversionError
    case imageTooLarge
    case serverError(String)
    case networkError(Error)
    case decodingError(Error)
    case noData
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Nieprawidłowy adres URL serwera"
        case .encodingError:
            return "Nie udało się zakodować danych do JSON"
        case .imageConversionError:
            return "Nie udało się przekonwertować obrazu na JPEG"
        case .imageTooLarge:
            return "Obraz jest za duży (maksimum 10MB)"
        case .serverError(let message):
            return "Błąd serwera: \(message)"
        case .networkError(let error):
            return "Błąd sieci: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Błąd dekodowania odpowiedzi: \(error.localizedDescription)"
        case .noData:
            return "Brak danych w odpowiedzi"
        }
    }
}

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
    
    private let aiURLSession: URLSession
    private let manualURLSession: URLSession
    
    init() {
        // Konfiguracja dla żądań AI (dłuższy timeout)
        let aiConfiguration = URLSessionConfiguration.default
        aiConfiguration.timeoutIntervalForRequest = NetworkConfig.aiRequestTimeout
        aiConfiguration.timeoutIntervalForResource = NetworkConfig.aiRequestTimeout
        self.aiURLSession = URLSession(configuration: aiConfiguration)
        
        // Konfiguracja dla żądań ręcznych (krótszy timeout)
        let manualConfiguration = URLSessionConfiguration.default
        manualConfiguration.timeoutIntervalForRequest = NetworkConfig.manualRequestTimeout
        manualConfiguration.timeoutIntervalForResource = NetworkConfig.manualRequestTimeout
        self.manualURLSession = URLSession(configuration: manualConfiguration)
    }
    
    // MARK: - Helper Methods
    
    private func validateImageSize(_ image: UIImage) -> Bool {
        guard let imageData = image.jpegData(compressionQuality: NetworkConfig.imageCompressionQuality) else {
            return false
        }
        return imageData.count <= NetworkConfig.maxImageSize
    }
    
    private func prepareImageForUpload(_ image: UIImage) -> (UIImage, Data)? {
        var imageToProcess = image
        
        // Sprawdź rozmiar przed kompresją
        if !validateImageSize(imageToProcess) {
            print("Obraz jest za duży, zmniejszam...")
        }
        
        // Zmniejsz jeśli za duży
        if image.size.width > NetworkConfig.targetImageWidth {
            print("Obraz jest za duży (\(image.size.width)px). Zmniejszam do \(NetworkConfig.targetImageWidth)px szerokości.")
            if let resizedImage = image.resized(toWidth: NetworkConfig.targetImageWidth) {
                imageToProcess = resizedImage
                print("Pomyślnie zmniejszono obraz do: \(imageToProcess.size)")
            } else {
                print("Nie udało się zmniejszyć obrazu, wysyłam oryginał.")
            }
        }
        
        guard let jpegData = imageToProcess.jpegData(compressionQuality: NetworkConfig.imageCompressionQuality) else {
            return nil
        }
        
        // Sprawdź rozmiar po kompresji
        if jpegData.count > NetworkConfig.maxImageSize {
            print("Ostrzeżenie: Obraz po kompresji nadal jest duży (\(jpegData.count) bajtów)")
        }
        
        return (imageToProcess, jpegData)
    }
    
    private func performRequest<T: Decodable>(
        with request: URLRequest,
        session: URLSession,
        responseType: T.Type,
        retryCount: Int = 0,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                // Obsługa błędów sieciowych z retry
                if let error = error {
                    let nsError = error as NSError
                    let isRetryable = nsError.code == NSURLErrorTimedOut ||
                                     nsError.code == NSURLErrorNetworkConnectionLost ||
                                     nsError.code == NSURLErrorNotConnectedToInternet
                    
                    if isRetryable && retryCount < NetworkConfig.maxRetryAttempts {
                        print("Błąd sieciowy, ponawiam próbę (\(retryCount + 1)/\(NetworkConfig.maxRetryAttempts))...")
                        DispatchQueue.main.asyncAfter(deadline: .now() + NetworkConfig.retryDelay) {
                            self.performRequest(
                                with: request,
                                session: session,
                                responseType: responseType,
                                retryCount: retryCount + 1,
                                completion: completion
                            )
                        }
                        return
                    }
                    
                    print("BŁĄD SIECIOWY: \(error.localizedDescription)")
                    completion(.failure(NetworkError.networkError(error)))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    completion(.failure(NetworkError.serverError("Nieprawidłowa odpowiedź serwera")))
                    return
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    let errorMessage = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Kod błędu: \(httpResponse.statusCode)"
                    print("BŁĄD SERWERA: \(errorMessage)")
                    completion(.failure(NetworkError.serverError(errorMessage)))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NetworkError.noData))
                    return
                }
                
                do {
                    let result = try JSONDecoder().decode(responseType, from: data)
                    print("SUKCES: Otrzymano wynik analizy.")
                    completion(.success(result))
                } catch {
                    print("BŁĄD DEKODOWANIA JSON: \(error)")
                    if let errorString = String(data: data, encoding: .utf8) {
                        print("Serwer zwrócił: \(errorString)")
                    }
                    completion(.failure(NetworkError.decodingError(error)))
                }
            }
        }.resume()
    }
    func analyzeImage(image: UIImage, targetBall: Point, pocket: Point, completion: @escaping (Result<AnalysisResult, Error>) -> Void) {
        print("Rozpoczynam analizę... cel: \(targetBall), łuza: \(pocket)")
        
        guard let serverURL = URL(string: "\(NetworkConfig.serverBaseURL)/analyze") else {
            completion(.failure(NetworkError.invalidURL))
            return
        }
        
        // 1. Przygotuj dane JSON do wysłania
        let requestData = RequestData(target_ball: targetBall, pocket: pocket)
        guard let jsonData = try? JSONEncoder().encode(requestData) else {
            completion(.failure(NetworkError.encodingError))
            return
        }
        
        // 2. Przygotuj obraz
        guard let (_, jpegData) = prepareImageForUpload(image) else {
            completion(.failure(NetworkError.imageConversionError))
            return
        }
        
        // 3. Stwórz żądanie 'multipart/form-data'
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Część 1: Pole 'data' (JSON)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"data\"\r\n\r\n".data(using: .utf8)!)
        body.append(jsonData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Część 2: Pole 'file' (Obraz)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpegData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Zakończenie
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        // 4. Wyślij żądanie z retry logic
        performRequest(
            with: request,
            session: aiURLSession,
            responseType: AnalysisResult.self,
            completion: completion
        )
    }
    func calculateManual(whiteBall: Point, targetBall: Point, pocket: Point, completion: @escaping (Result<AnalysisResult, Error>) -> Void) {
        print("Rozpoczynam analizę RĘCZNĄ... biała: \(whiteBall), cel: \(targetBall), łuza: \(pocket)")

        guard let serverURL = URL(string: "\(NetworkConfig.serverBaseURL)/calculate_manual") else {
            completion(.failure(NetworkError.invalidURL))
            return
        }

        // 1. Przygotuj dane JSON (3 punkty)
        let requestData = RequestDataManual(white_ball: whiteBall, target_ball: targetBall, pocket: pocket)
        guard let jsonData = try? JSONEncoder().encode(requestData) else {
            completion(.failure(NetworkError.encodingError))
            return
        }

        // 2. Stwórz proste żądanie JSON (bez obrazu)
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        // 3. Wyślij żądanie z retry logic
        performRequest(
            with: request,
            session: manualURLSession,
            responseType: AnalysisResult.self,
            completion: completion
        )
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

