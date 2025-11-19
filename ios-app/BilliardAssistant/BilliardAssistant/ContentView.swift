import SwiftUI

struct ContentView: View {
    // 1. Stan, który kontroluje, czy pokazywać ekran startowy
    @State private var isActive = false

    var body: some View {
        ZStack {
            if self.isActive {
                // 2. Po zakończeniu timera, pokaż główny widok kamery
                CameraView()
                    .preferredColorScheme(.dark) // Wymuś tryb ciemny, aby pasował
            } else {
                // 3. Na starcie, pokaż ekran startowy
                SplashView()
            }
        }
        .onAppear {
            // 4. Uruchom timer, gdy tylko widok się pojawi
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                // Po 2.5 sekundach...
                withAnimation {
                    self.isActive = true // ...przełącz na CameraView z płynną animacją
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
