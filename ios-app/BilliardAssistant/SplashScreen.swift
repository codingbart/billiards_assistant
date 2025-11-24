import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack {
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
