import AppKit
import AVFoundation

/// 알람(시스템 소리)과 집중 중 배경음(코드로 만드는 노이즈·똑딱 소리).
final class PomodoroSound {
    private var engine: AVAudioEngine?
    private var current: PomodoroSettings.Noise = .none
    private var alarm: NSSound?

    /// `/System/Library/Sounds`의 소리 이름
    static let alarmNames: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files.map { ($0 as NSString).deletingPathExtension }.sorted()
    }()

    func playAlarm(_ name: String, volume: Double) {
        alarm?.stop()
        alarm = NSSound(named: NSSound.Name(name))
        alarm?.volume = Float(volume)
        alarm?.play()
    }

    func setNoise(_ noise: PomodoroSettings.Noise, volume: Double) {
        engine?.mainMixerNode.outputVolume = Float(volume)
        guard noise != current else { return }
        engine?.stop()
        engine = nil
        current = noise
        guard noise != .none else { return }
        let e = AVAudioEngine()
        let format = e.outputNode.inputFormat(forBus: 0)
        let node = NoiseSource.make(noise, sampleRate: format.sampleRate)
        let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)
        e.attach(node)
        e.connect(node, to: e.mainMixerNode, format: mono)
        e.mainMixerNode.outputVolume = Float(volume)
        do {
            try e.start()
            engine = e
        } catch {
            current = .none
        }
    }
}

/// 오디오 스레드에서 도는 노이즈 생성기
private nonisolated enum NoiseSource {
    final class State: @unchecked Sendable {
        var b0 = 0.0, b1 = 0.0, b2 = 0.0, brown = 0.0
        var sample = 0
    }

    static func make(_ noise: PomodoroSettings.Noise, sampleRate: Double) -> AVAudioSourceNode {
        let state = State()
        let click = Int(sampleRate * 0.012)
        return AVAudioSourceNode { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            for frame in 0..<Int(frameCount) {
                let white = Double.random(in: -1...1)
                var v: Double
                switch noise {
                case .white: v = white * 0.25
                case .pink:
                    // Paul Kellet 근사 필터
                    state.b0 = 0.99765 * state.b0 + white * 0.0990460
                    state.b1 = 0.96300 * state.b1 + white * 0.2965164
                    state.b2 = 0.57000 * state.b2 + white * 1.0526913
                    v = (state.b0 + state.b1 + state.b2 + white * 0.1848) * 0.08
                case .brown:
                    state.brown = (state.brown + 0.02 * white) / 1.02
                    v = state.brown * 2.5
                case .ticking:
                    // 1초마다 짧게 감쇠하는 딸깍 소리
                    let k = state.sample % Int(sampleRate)
                    v = k < click ? sin(Double(k) * 2 * .pi * 1800 / sampleRate) * exp(-Double(k) / Double(click) * 5) * 0.6 : 0
                case .none: v = 0
                }
                state.sample += 1
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = Float(v)
                }
            }
            return noErr
        }
    }
}
