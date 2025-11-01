//
//  MagnifyingLoupeView.swift
//  BilliardAssistant
//
//  Created by Bartłomiej Karkoszka on 01/11/2025.
//


import SwiftUI

struct MagnifyingLoupeView: View {
    let image: UIImage
    let touchPoint: CGPoint // Punkt dotyku na ekranie
    let imageFrame: CGRect  // Ramka obrazka na ekranie
    
    var body: some View {
        let loupeSize: CGFloat = 110 // Rozmiar naszej lupy
        let magnification: CGFloat = 2.5 // Stopień powiększenia

        // 1. Przelicz pozycję dotyku na ekranie na pozycję procentową (%) na obrazku
        //    (np. 0.5 = środek obrazka)
        let relativeX = (touchPoint.x - imageFrame.origin.x) / imageFrame.width
        let relativeY = (touchPoint.y - imageFrame.origin.y) / imageFrame.height

        // 2. Upewnij się, że nie rysujemy lupy poza obrazkiem
        let clampedRelativeX = min(max(relativeX, 0), 1)
        let clampedRelativeY = min(max(relativeY, 0), 1)

        // 3. Zwróć widok lupy
        return AnyView(
            ZStack {
                // Bierzemy cały obrazek, powiększamy go 2.5x...
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill() // Używamy .scaledToFill, aby powiększyć
                    .frame(width: imageFrame.width * magnification, height: imageFrame.height * magnification)
                
                    // ...i przesuwamy go tak, aby punkt dotyku znalazł się
                    // idealnie w centrum naszej lupy
                    .offset(
                            x: -clampedRelativeX * (imageFrame.width * magnification) + (loupeSize / 2),
                            y: -clampedRelativeY * (imageFrame.height * magnification) + (loupeSize / 2)
                    )
            }
            .frame(width: loupeSize, height: loupeSize) // Przycinamy obrazek do rozmiaru lupy
            .clipShape(Circle()) // Nadajemy mu kształt koła
            .overlay(
                // Dodajemy ramkę i celownik
                ZStack {
                    Circle().stroke(Color.primary, lineWidth: 2)
                    Rectangle().fill(Color.red).frame(width: 1, height: loupeSize) // Pionowy celownik
                    Rectangle().fill(Color.red).frame(width: loupeSize, height: 1) // Poziomy celownik
                }
            )
            .shadow(radius: 5) // Dodajemy cień, by lupa "wyskoczyła" z ekranu
        )
    }
}
