//
//  SpeechManager.swift
//  SensePath
//
//  语音播报管理器 - 使用 AVSpeechSynthesizer 提供语音提示
//

import AVFoundation

// MARK: - Priority

enum SpeechPriority {
    case low
    case normal
    case high
}

// MARK: - Main Class

class SpeechManager: NSObject {
    
    // MARK: Properties
    
    var isEnabled = true
    
    private let synthesizer = AVSpeechSynthesizer()
    private var speechQueue: [(text: String, priority: SpeechPriority)] = []
    private var isSpeaking = false
    
    // MARK: Initialization
    
    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }
    
    // MARK: Public Methods
    
    /// 播报文本
    func speak(_ text: String, priority: SpeechPriority = .normal) {
        guard isEnabled else { return }
        
        switch priority {
        case .high:
            // 高优先级：立即打断当前播报
            synthesizer.stopSpeaking(at: .immediate)
            speechQueue.removeAll()
            speakImmediately(text)
            
        case .normal:
            // 普通优先级：排队
            speechQueue.append((text, priority))
            processQueue()
            
        case .low:
            // 低优先级：如果正在播报则跳过
            if !isSpeaking {
                speechQueue.append((text, priority))
                processQueue()
            }
        }
    }
    
    /// 停止播报
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speechQueue.removeAll()
        isSpeaking = false
    }
    
    // MARK: - Private Methods
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // 使用 ambient 模式，允许用户听到环境音
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            print("❌ 音频会话配置失败: \(error)")
        }
    }
    
    private func speakImmediately(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = 0.55  // 稍快一点
        utterance.volume = 1.0
        
        isSpeaking = true
        synthesizer.speak(utterance)
    }
    
    private func processQueue() {
        guard !isSpeaking, !speechQueue.isEmpty else { return }
        
        let next = speechQueue.removeFirst()
        speakImmediately(next.text)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechManager: AVSpeechSynthesizerDelegate {
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        processQueue()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
        processQueue()
    }
}
