import SwiftUI

extension CameraView {
    // --- LOGIKA ---
    func setMode(table: Bool) {
        isSelectingTableArea = table
        isCalibrating = false
    }
    
    func runDetection() {
        guard let img = capturedImage else { return }
        isLoading = true; errorMessage = nil
        networkManager.detectBalls(image: img, tableArea: tableCorners, calibrationPoint: calibrationPoint) { res in
            isLoading = false
            switch res {
            case .success(let balls):
                self.detectedBalls = balls
                if balls.isEmpty { self.errorMessage = "Nie wykryto bil. Spróbuj skalibrować tło." }
                else { self.currentStep = .verifying }
            case .failure(let err): self.errorMessage = "Błąd: \(err.localizedDescription)"
            }
        }
    }
    
    func runCalculation() {
        isLoading = true; errorMessage = nil
        networkManager.calculateShot(balls: detectedBalls, pockets: pockets, tableArea: tableCorners, cueBallColor: cueBallColor) { res in
            isLoading = false
            switch res {
            case .success(let result):
                self.bestShotResult = result
                self.currentStep = .result
            case .failure(let err): self.errorMessage = "Błąd: \(err.localizedDescription)"
            }
        }
    }
    
    func handleTap(at location: CGPoint, imageSize: CGSize, viewSize: CGSize) {
        guard let p = CoordinateHelpers.convertFromViewToImage(
            point: location,
            imageSize: imageSize,
            viewSize: viewSize
        ) else { return }
        let point = CGPoint(x: p.x, y: p.y)
        
        if isCalibrating {
            calibrationPoint = point
            isCalibrating = false
        } else if isSelectingTableArea {
            if tableCorners.count < 4 { tableCorners.append(point) }
            else { tableCorners = [point] }
        } else {
            pockets.append(point)
        }
    }
    
    func cycleColor(for ball: inout DetectedBall) {
        if let idx = availableColors.firstIndex(of: ball.ballClass.capitalized) {
            ball.ballClass = availableColors[(idx + 1) % availableColors.count]
        } else { ball.ballClass = "White" }
    }
    
    func resetAll() {
        capturedImage = nil
        pockets = []
        tableCorners = []
        detectedBalls = []
        bestShotResult = nil
        calibrationPoint = nil
        isCalibrating = false
        currentStep = .marking
        errorMessage = nil
    }
}

