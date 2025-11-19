import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            // Możesz tu ustawić dowolny kolor tła
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack {
                // Prosta ikona - możesz ją zastąpić własnym logo
                Image(systemName: "circle.grid.cross.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .foregroundColor(.white)
                
                Text("Asystent Bilardowy")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 20)
            }
        }
    }
}

#Preview {
    SplashView()
}
