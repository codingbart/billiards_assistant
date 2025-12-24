import SwiftUI

struct DrawingHelpers {
    static func drawTableAndPockets(
        tableCorners: [CGPoint],
        pockets: [CGPoint],
        scale: CGFloat,
        offset: CGPoint
    ) -> some View {
        Group {
            if !tableCorners.isEmpty {
                Path { path in
                    for (i, p) in tableCorners.enumerated() {
                        let vp = CoordinateHelpers.convert(p, scale, offset)
                        i == 0 ? path.move(to: vp) : path.addLine(to: vp)
                    }
                    if tableCorners.count == 4 { path.closeSubpath() }
                }.stroke(Color.yellow, lineWidth: 2)
            }
            
            ForEach(pockets.indices, id: \.self) { i in
                Circle()
                    .fill(Color.green)
                    .frame(width: 20, height: 20)
                    .position(CoordinateHelpers.convert(pockets[i], scale, offset))
            }
        }
    }
    
    static func drawBallsForVerification(
        detectedBalls: Binding<[DetectedBall]>,
        availableColors: [String],
        scale: CGFloat,
        offset: CGPoint
    ) -> some View {
        ForEach(detectedBalls) { $ball in
            let center = CoordinateHelpers.convert(CGPoint(x: ball.x, y: ball.y), scale, offset)
            let r = CGFloat(ball.r) * scale
            
            Button(action: {
                if let idx = availableColors.firstIndex(of: ball.ballClass.capitalized) {
                    ball.ballClass = availableColors[(idx + 1) % availableColors.count]
                } else {
                    ball.ballClass = "White"
                }
            }) {
                ZStack {
                    if ball.ballClass == "Ignore" {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                    } else {
                        Circle().stroke(UIHelpers.colorForClass(ball.ballClass), lineWidth: 3)
                            .background(Circle().fill(UIHelpers.colorForClass(ball.ballClass).opacity(0.3)))
                            .frame(width: max(24, r*2), height: max(24, r*2))
                        Text(ball.ballClass.prefix(1).uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(radius: 1)
                    }
                }
            }
            .position(center)
        }
    }
    
    @ViewBuilder
    static func drawBestShot(
        result: BestShotResult,
        scale: CGFloat,
        offset: CGPoint
    ) -> some View {
        let shot = result.best_shot
        
        // Główna linia (zielona)
        if let l1 = shot.shot_lines.first {
            let s = CoordinateHelpers.convert(CGPoint(x: l1.start.x, y: l1.start.y), scale, offset)
            let e = CoordinateHelpers.convert(CGPoint(x: l1.end.x, y: l1.end.y), scale, offset)
            Path { p in p.move(to: s); p.addLine(to: e) }.stroke(Color.green, lineWidth: 4)
        }
        
        // Linia pomocnicza (biała przerywana)
        if shot.shot_lines.count > 1 {
            let l2 = shot.shot_lines[1]
            let s = CoordinateHelpers.convert(CGPoint(x: l2.start.x, y: l2.start.y), scale, offset)
            let e = CoordinateHelpers.convert(CGPoint(x: l2.end.x, y: l2.end.y), scale, offset)
            Path { p in p.move(to: s); p.addLine(to: e) }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, dash: [5]))
        }
        
        // Ghost ball
        let ghost = CoordinateHelpers.convert(CGPoint(x: shot.ghost_ball.center.x, y: shot.ghost_ball.center.y), scale, offset)
        let r = CGFloat(shot.ghost_ball.radius) * scale
        Circle().stroke(Color.white, lineWidth: 2)
            .frame(width: r * 2, height: r * 2)
            .position(ghost)
        
        // Target ball (czerwony punkt)
        let target = CoordinateHelpers.convert(CGPoint(x: shot.target_ball.x, y: shot.target_ball.y), scale, offset)
        Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)
            .position(target)
    }
}

