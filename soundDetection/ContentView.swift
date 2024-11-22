import SwiftUI

struct ContentView: View {
    @StateObject private var microphoneMonitor = MicrophoneMonitor()

    var body: some View {
        VStack {
            Text("Microphone Sound Level")
                .font(.headline)
            
            // Affichez les niveaux de son capturés
            //LineGraph(data: microphoneMonitor.soundSamples)
            //    .frame(height: 200)
            
            Text(microphoneMonitor.isSouffling ? "Souffle détecté" : "")
            Text(microphoneMonitor.isSiffling ? "Sifflement détecté" : "")
            
            Button(action: {
                microphoneMonitor.startMonitoring()
            }) {
                Text("Start Monitoring")
            }
            
            Button(action: {
                microphoneMonitor.stopMonitoring()
            }) {
                Text("Stop Monitoring")
            }
            
            
        }
        .padding()
    }
}

struct LineGraph: View {
    var data: [Float]

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard !data.isEmpty else { return }

                let width = geometry.size.width
                let height = geometry.size.height
                let step = width / CGFloat(data.count - 1)
                let maxAmplitude = data.max() ?? 1

                for (index, sample) in data.enumerated() {
                    let x = CGFloat(index) * step
                    let normalizedSample = sample / maxAmplitude
                    let y = height * (1 - CGFloat(normalizedSample))
                    
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.blue, lineWidth: 2)
        }
    }
}
