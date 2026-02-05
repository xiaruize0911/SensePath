//
//  HapticsManager.swift
//  SensePath
//
//  触觉反馈管理器 - 使用 Core Haptics 提供方向和紧迫度编码的触觉反馈
//

import CoreHaptics
import UIKit

// MARK: - Haptic Pattern

enum HapticPattern {
    case directionLeft(urgency: Float)
    case directionRight(urgency: Float)
    case stop
    case lowConfidence
    case none
}

// MARK: - Main Class

class HapticsManager {
    
    // MARK: Properties
    
    private var engine: CHHapticEngine?
    private var isEngineRunning = false
    private var currentPattern: HapticPattern = .none
    private var patternTimer: Timer?
    
    // MARK: Initialization
    
    init() {
        setupEngine()
    }
    
    deinit {
        stop()
    }
    
    // MARK: Public Methods
    
    /// 启动触觉引擎
    func start() throws {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            throw HapticsError.notSupported
        }
        
        if engine == nil {
            setupEngine()
        }
        
        try engine?.start()
        isEngineRunning = true
    }
    
    /// 停止触觉引擎
    func stop() {
        patternTimer?.invalidate()
        patternTimer = nil
        currentPattern = .none
        
        // 停止引擎时使用 completion 取消运行标记
        engine?.stop(completionHandler: { [weak self] _ in
            self?.isEngineRunning = false
        })
        isEngineRunning = false
    }
    
    /// 播放触觉模式
    func playPattern(_ pattern: HapticPattern) {
        guard isEngineRunning else { return }
        
        // 如果模式改变，停止当前播放
        if pattern != currentPattern {
            patternTimer?.invalidate()
            currentPattern = pattern
        }
        
        switch pattern {
        case .directionLeft(let urgency):
            playDirectionLeft(urgency: urgency)
            
        case .directionRight(let urgency):
            playDirectionRight(urgency: urgency)
            
        case .stop:
            playStop()
            
        case .lowConfidence:
            playLowConfidence()
            
        case .none:
            patternTimer?.invalidate()
        }
    }
    
    // MARK: - Private Setup
    
    private func setupEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("⚠️ 设备不支持触觉反馈")
            return
        }
        
        do {
            engine = try CHHapticEngine()
            
            // 处理引擎重置
            engine?.resetHandler = { [weak self] in
                print("🔄 触觉引擎重置")
                do {
                    try self?.engine?.start()
                    self?.isEngineRunning = true
                } catch {
                    print("❌ 引擎重启失败: \(error)")
                }
            }
            
            // 处理引擎停止
            engine?.stoppedHandler = { reason in
                print("⏸️ 触觉引擎停止: \(reason)")
            }
            
        } catch {
            print("❌ 创建触觉引擎失败: \(error)")
        }
    }
    
    // MARK: - Pattern Implementations
    
    /// 向左提示：双脉冲，间隔 0.1s
    private func playDirectionLeft(urgency: Float) {
        let interval = calculateInterval(urgency: urgency, baseInterval: 1.0)
        
        scheduleRepeating(interval: interval) { [weak self] in
            self?.playDoubleImpact(intensity: 0.5 + urgency * 0.5)
        }
    }
    
    /// 向右提示：单长脉冲，0.2s
    private func playDirectionRight(urgency: Float) {
        let interval = calculateInterval(urgency: urgency, baseInterval: 1.0)
        
        scheduleRepeating(interval: interval) { [weak self] in
            self?.playSingleLongImpact(duration: 0.2, intensity: 0.5 + urgency * 0.5)
        }
    }
    
    /// 停止提示：连续强震动
    private func playStop() {
        scheduleRepeating(interval: 0.5) { [weak self] in
            self?.playContinuousImpact(duration: 0.3, intensity: 1.0, sharpness: 1.0)
        }
    }
    
    /// 低可靠提示：轻微震动一次，提示用户注意，不循环
    private func playLowConfidence() {
        patternTimer?.invalidate()
        playContinuousImpact(duration: 0.2, intensity: 0.4, sharpness: 0.2)
    }
    
    // MARK: - Primitive Patterns
    
    /// 双脉冲
    private func playDoubleImpact(intensity: Float) {
        var events: [CHHapticEvent] = []
        
        // 第一个脉冲
        events.append(CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
            ],
            relativeTime: 0
        ))
        
        // 第二个脉冲（间隔 0.1s）
        events.append(CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
            ],
            relativeTime: 0.1
        ))
        
        playEvents(events)
    }
    
    /// 单长脉冲
    private func playSingleLongImpact(duration: TimeInterval, intensity: Float) {
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ],
            relativeTime: 0,
            duration: duration
        )
        
        playEvents([event])
    }
    
    /// 连续震动
    private func playContinuousImpact(duration: TimeInterval, intensity: Float, sharpness: Float) {
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0,
            duration: duration
        )
        
        playEvents([event])
    }
    
    // MARK: - Helpers
    
    private func playEvents(_ events: [CHHapticEvent]) {
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("❌ 播放触觉失败: \(error)")
        }
    }
    
    private func scheduleRepeating(interval: TimeInterval, action: @escaping () -> Void) {
        patternTimer?.invalidate()
        
        // 立即执行一次
        action()
        
        // 定时重复
        patternTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            action()
        }
    }
    
    /// 计算重复间隔（紧迫度越高，间隔越短）
    private func calculateInterval(urgency: Float, baseInterval: TimeInterval) -> TimeInterval {
        let minInterval = 0.3
        let maxInterval = baseInterval
        return maxInterval - Double(urgency) * (maxInterval - minInterval)
    }
}

// MARK: - Error

enum HapticsError: Error, LocalizedError {
    case notSupported
    case engineFailed
    
    var errorDescription: String? {
        switch self {
        case .notSupported:
            return "设备不支持触觉反馈"
        case .engineFailed:
            return "触觉引擎初始化失败"
        }
    }
}

// MARK: - Equatable for HapticPattern

extension HapticPattern: Equatable {
    static func == (lhs: HapticPattern, rhs: HapticPattern) -> Bool {
        switch (lhs, rhs) {
        case (.directionLeft, .directionLeft),
             (.directionRight, .directionRight),
             (.stop, .stop),
             (.lowConfidence, .lowConfidence),
             (.none, .none):
            return true
        default:
            return false
        }
    }
}
