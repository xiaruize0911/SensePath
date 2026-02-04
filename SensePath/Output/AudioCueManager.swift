//
//  AudioCueManager.swift
//  SensePath
//
//  音频提示管理器 - 播放简短的提示音
//

import AVFoundation
import AudioToolbox

class AudioCueManager {
    
    // MARK: Properties
    
    private var isEnabled = true
    
    // MARK: Public Methods
    
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }
    
    /// 播放提示音（beep）
    func playBeep(frequency: Float = 800, duration: TimeInterval = 0.1) {
        guard isEnabled else { return }
        
        // 使用系统音效（简单实现）
        AudioServicesPlaySystemSound(1103)  // Tink sound
    }
    
    /// 播放停止音
    func playStopSound() {
        guard isEnabled else { return }
        
        AudioServicesPlaySystemSound(1013)  // Alert sound
    }
    
    /// 播放警告音
    func playWarningSound() {
        guard isEnabled else { return }
        
        AudioServicesPlaySystemSound(1052)  // Warning sound
    }
}
