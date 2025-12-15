import Foundation
import UIKit

// --- WSPÓLNE MODELE DANYCH ---

// Krok 1: Wynik detekcji (z backendu)
struct DetectionResponse: Codable {
    let balls: [DetectedBall]
}

// Krok 2: Wynik obliczeń (z backendu)
struct CalculationResponse: Codable {
    let best_shot: BestShotDetail
}

// Główny model bili (używany w widoku i komunikacji)
// Dodano 'id' do obsługi pętli w SwiftUI
struct DetectedBall: Codable, Identifiable, Equatable {
    var id = UUID()
    var x: Int
    var y: Int
    var r: Int
    var ballClass: String // np. "red", "white", "black"
    
    // CodingKeys - pomijamy 'id' przy wysyłaniu do serwera
    enum CodingKeys: String, CodingKey {
        case x, y, r
        case ballClass = "class"
    }
}

// Wrapper wyniku końcowego
struct BestShotResult: Codable {
    let best_shot: BestShotDetail
}

// Szczegóły strzału
struct BestShotDetail: Codable {
    let target_ball: Ball
    let pocket: Point
    let angle: Double
    let shot_lines: [Line]
    let ghost_ball: GhostBall
}

// Pomocnicze struktury geometryczne
struct Ball: Codable {
    let r, x, y: Int
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