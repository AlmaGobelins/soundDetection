import Foundation
import AVFoundation
import Combine
import Accelerate

class MicrophoneMonitor: ObservableObject {
    private var audioEngine: AVAudioEngine
    private var inputNode: AVAudioInputNode
    private var audioFormat: AVAudioFormat

    @Published var soundSamples: [[Float]] = []
    @Published var isSouffling:Bool = false
    @Published var isSiffling:Bool = false
    
    init() {
        self.audioEngine = AVAudioEngine()
        self.inputNode = audioEngine.inputNode
        self.audioFormat = inputNode.inputFormat(forBus: 0) // Format matériel
        configureAudioSession()
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setPreferredSampleRate(audioFormat.sampleRate)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("Audio session configured with sample rate: \(audioFormat.sampleRate)")
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    func startMonitoring() {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: audioFormat) { [weak self] (buffer, time) in
            self?.processAudioBuffer(buffer)
        }

        do {
            try audioEngine.start()
        } catch {
            print("AudioEngine couldn't start: \(error)")
        }
    }
    
    func applyWindow(_ signal:[Float]) -> [Float] {
    //    // Hamming
        let size = signal.count
        var windowedSignal = [Float](repeating: 0.0, count: size)
        var window = [Float](repeating: 0.0, count: size)
        vDSP_hamm_window(&window, UInt(size), 0)
        vDSP_vmul(signal, 1, window, 1, &windowedSignal, 1, UInt(size))
        return windowedSignal
    }

    func substracValue(_ values:Float, toSignal signal:[Float]) -> [Float] {
        
        let size = signal.count
        var sub:[Float] = [Float](repeating: -values, count: size)
        var substractedValues = [Float](repeating: 0.0, count: Int(size))
        vDSP_vsub(signal, 1, &sub, 1, &substractedValues, 1, vDSP_Length(size))
        return substractedValues
    }


    func meanOfSignal(_ values:[Float]) -> Float {
        var mean:Float = 0
        vDSP_meanv(values, 1, &mean, vDSP_Length(values.count))
        return mean
    }

    public func normalizeFFT(_ values:[Float]) -> [Float] {
        
        var size = values.count
        var normalizedValues = [Float](repeating: 0.0, count: Int(size))
        var origninalSize = Float(values.count*2)
        vDSP_vsmul(values, 1, &origninalSize, &normalizedValues, 1, vDSP_Length(Int(size)))
        
        return normalizedValues
    }

    func normalize(_ values:[Float]) -> [Float] {
        if let min = values.min(),
            let max = values.max() {
            
            return values.map{ Rescale(from: (min,max), to: (0,1)).rescale($0) }
            
        }else{
            return values
        }
        
    }

    public func squareValues(_ values:[Float]) -> [Float] {
        let size = values.count
        var squaredValues = [Float](repeating: 0.0, count: size)
        vDSP_vsq(values, 1, &squaredValues, 1, vDSP_Length(size))
        return squaredValues
    }
    
    public func fft(_ input: [Float]) -> (real:[Float], img:[Float]) {
        
        var real = input
        let size = real.count
        
        var imaginary = [Float](repeating: 0.0, count: input.count)
        var splitComplex = DSPSplitComplex(realp: &real, imagp: &imaginary)
        
        let length = vDSP_Length(floor(log2(Float(size))))
        let radix = FFTRadix(kFFTRadix5)
        let weights = vDSP_create_fftsetup(length, radix)
        
        vDSP_fft_zip(weights!, &splitComplex, 1, length, FFTDirection(FFT_FORWARD))
        
        vDSP_destroy_fftsetup(weights)
        
        return (real,imaginary)
    }

    func splitArrayIntoChunks(array: [Float], chunkSize: Int) -> [[Float]] {
        // Utilisez stride pour découper le tableau
        return stride(from: 0, to: array.count, by: chunkSize).map { startIndex in
            let endIndex = min(startIndex + chunkSize, array.count)
            return Array(array[startIndex..<endIndex])
        }
    }
    
    func spectrogramValuesForSignal(input: [Float], chunkSize:Int = 1024) -> [[Float]] {
        
        let signalMean = meanOfSignal(input)
        let signal = substracValue(signalMean, toSignal: input)
        let windowedSignal = applyWindow(input)
        let signalAudio = windowedSignal.chunks(chunkSize)
        let normalizedMagnitudes:[[Float]] = signalAudio.map{
            let fftValues = fft($0)
            let real = fftValues.real
            return normalizeFFT(squareValues(Array(real[0...real.count/2])))
        }
        return normalizedMagnitudes
    }


    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let channelDataArray = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))

            
        
        let rms = sqrt(channelDataArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        print(rms)
        if rms > 0.3 {
            DispatchQueue.main.async {
                self.isSouffling = true
            }
        }else{
            DispatchQueue.main.async {
                self.isSouffling = false
            }
        }
        
        let spec = self.spectrogramValuesForSignal(input: channelDataArray, chunkSize: 2048*8)
        for s in spec {
            if let m = s.max(){
                if let currentIdx = s.index(of: m){
                    if currentIdx > 110 && currentIdx < 130 {
                        DispatchQueue.main.async {
                            self.isSiffling = true
                        }
                    }else{
                        DispatchQueue.main.async {
                            self.isSiffling = false
                        }
                    }
                }
            }
        }
        DispatchQueue.main.async {
            self.soundSamples.append(channelDataArray)
            if self.soundSamples.count > 30 {
                self.soundSamples.removeFirst()
            }
        }
    }

    func stopMonitoring() {
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
    }
}
