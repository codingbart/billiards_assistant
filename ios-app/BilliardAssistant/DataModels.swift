import Foundation
import UIKit

// --- WSPÓLNE MODELE DANYCH ---

// Krok 1: Wynik detekcji
struct DetectionResponse: Codable {
    let balls: [DetectedBall]
}

// Krok 2: Wynik obliczeń
struct CalculationResponse: Codable {
    let best_shot: BestShotDetail
}

// Bila do edycji
struct DetectedBall: Codable, Identifiable, Equatable {
    var id = UUID()
    var x: Int
    var y: Int
    var r: Int
    var ballClass: String
    
    enum CodingKeys: String, CodingKey {
        case x, y, r
        case ballClass = "class"
    }
}

// Wynik końcowy
struct BestShotResult: Codable {
    let best_shot: BestShotDetail
}

struct BestShotDetail: Codable {
    let target_ball: Ball
    let pocket: Point
    let angle: Double
    let shot_lines: [Line]
    let ghost_ball: GhostBall
}

struct Ball: Codable { let r, x, y: Int }
struct Line: Codable { let start, end: Point }
struct Point: Codable { let x, y: Int }
struct GhostBall: Codable { let center: Point; let radius: Int }
