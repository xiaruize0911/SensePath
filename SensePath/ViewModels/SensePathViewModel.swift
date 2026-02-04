//
//  SensePathViewModel.swift
//  SensePath
//
//  主协调器 - 连接所有模块并管理应用状态
//

import Foundation
import AVFoundation
import Combine
import UIKit

class SensePathViewModel: ObservableObject {
    
    // MARK: Published State
    
    @Published var isRunning = false
    @Published var currentState: GuidanceState = .normal
    @Published var urgency: Float = 0
    @Published var debugInfo: String = ""
    @Published var errorMessage: String?
    @Published var fps: Double = 0
    @Published var heatmapImage: UIImage? = nil
    @Published var originalImage: UIImage? = nil
    
    // 详细指标（调试用）
    @Published var leftDistance: Float = 0
    @Published var centerDistance: Float = 0
    @Published var rightDistance: Float = 0
    @Published var invalidRatio: Float = 0
    @Published var stability: Float = 0
    
    // MARK: Dependencies
    
    let settings: SettingsManager
    
    private let captureManager = DepthCaptureManager()
    private var analyzer: DepthAnalyzer
    private var stateMachine: GuidanceStateMachine
    private let heatmapRenderer = HeatmapRenderer()
    
    private let hapticsManager = HapticsManager()
    private let audioManager = AudioCueManager()
    private let speechManager = SpeechManager()
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: Initialization
    
    init(settings: SettingsManager) {
        self.settings = settings
        self.analyzer = DepthAnalyzer(config: settings.currentAnalyzerConfig)
        self.stateMachine = GuidanceStateMachine(thresholds: settings.currentGuidanceThresholds)
        
        setupBindings()
        captureManager.delegate = self
    }
    
    // MARK: Public Methods
    
    /// 启动避障
    func start() {
        guard !isRunning else { return }
        
        // 检查深度可用性
        guard captureManager.isDepthAvailable() else {
            errorMessage = "此设备不支持深度检测（需要 TrueDepth 相机）"
            return
        }
        
        do {
            // 启动触觉
            try hapticsManager.start()
            
            // 启动采集
            try captureManager.startCapture()
            
            // 重置状态
            analyzer.reset()
            stateMachine.reset()
            
            isRunning = true
            errorMessage = nil
            
            // 语音提示
            if settings.outputMode == .hapticSpeech {
                speechManager.speak("避障已启动", priority: .normal)
            }
            
        } catch {
            errorMessage = "启动失败: \(error.localizedDescription)"
            isRunning = false
        }
    }
    
    /// 停止避障
    func stop() {
        guard isRunning else { return }
        
        captureManager.stopCapture()
        hapticsManager.stop()
        speechManager.stop()
        
        isRunning = false
        currentState = .normal
        urgency = 0
        
        // 语音提示
        if settings.outputMode == .hapticSpeech {
            speechManager.speak("避障已停止", priority: .normal)
        }
    }
    
    // MARK: - Private Setup
    
    private func setupBindings() {
        // 监听设置变化
        settings.$sensitivity
            .sink { [weak self] sensitivity in
                guard let self = self else { return }
                self.analyzer.config = sensitivity.analyzerConfig
                self.stateMachine.thresholds = sensitivity.guidanceThresholds
            }
            .store(in: &cancellables)
        
        settings.$stopThreshold
            .sink { [weak self] value in
                guard let self = self else { return }
                self.stateMachine.thresholds.stopDistance = value
            }
            .store(in: &cancellables)
        
        settings.$warnThreshold
            .sink { [weak self] value in
                guard let self = self else { return }
                self.stateMachine.thresholds.warnDistance = value
            }
            .store(in: &cancellables)
        
        settings.$outputMode
            .sink { [weak self] mode in
                guard let self = self else { return }
                self.updateOutputMode(mode)
            }
            .store(in: &cancellables)
    }
    
    private func updateOutputMode(_ mode: OutputMode) {
        switch mode {
        case .hapticOnly:
            audioManager.setEnabled(false)
            speechManager.isEnabled = false
            
        case .hapticBeep:
            audioManager.setEnabled(true)
            speechManager.isEnabled = false
            
        case .hapticSpeech:
            audioManager.setEnabled(false)
            speechManager.isEnabled = true
        }
    }
    
    // MARK: - Processing Pipeline
    
    private func processFrame(depthData: AVDepthData, sampleBuffer: CMSampleBuffer) {
        // 1. 分析深度
        let (sectorDepth, quality) = analyzer.analyze(depthData: depthData, fps: captureManager.currentFPS)
        
        // 2. 更新状态机
        let guidance = stateMachine.update(sectorDepth: sectorDepth, quality: quality)
        
        // 3. 渲染调试图（如果需要）
        var heatmap: UIImage? = nil
        var original: UIImage? = nil
        if settings.showMetrics {
            heatmap = heatmapRenderer.render(
                depthBuffer: depthData.depthDataMap,
                minDistance: 0.5,
                maxDistance: 4.0
            )
            
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                original = heatmapRenderer.convert(pixelBuffer: pixelBuffer)
            }
        }
        
        // 4. 更新 UI（主线程）
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.currentState = guidance.state
            self.urgency = guidance.urgency
            self.debugInfo = guidance.debugInfo
            self.fps = quality.fps
            self.heatmapImage = heatmap
            self.originalImage = original
            
            // 详细指标
            if self.settings.showMetrics {
                self.leftDistance = sectorDepth.left
                self.centerDistance = sectorDepth.center
                self.rightDistance = sectorDepth.right
                self.invalidRatio = sectorDepth.invalidRatio
                self.stability = sectorDepth.stability
            }
        }
        
        // 5. 输出触觉
        let hapticPattern = mapToHapticPattern(state: guidance.state, urgency: guidance.urgency)
        hapticsManager.playPattern(hapticPattern)
        
        // 6. 语音（仅状态变化时）
        if guidance.stateChanged, let message = guidance.message {
            handleStateChange(state: guidance.state, message: message)
        }
    }
    
    // MARK: - Output Mapping
    
    private func mapToHapticPattern(state: GuidanceState, urgency: Float) -> HapticPattern {
        switch state {
        case .warningLeft:
            return .directionLeft(urgency: urgency)
        case .warningRight:
            return .directionRight(urgency: urgency)
        case .stop:
            return .stop
        case .lowConfidence:
            return .lowConfidence
        case .normal:
            return .none
        }
    }
    
    private func handleStateChange(state: GuidanceState, message: String) {
        switch settings.outputMode {
        case .hapticOnly:
            break
            
        case .hapticBeep:
            switch state {
            case .stop:
                audioManager.playStopSound()
            case .warningLeft, .warningRight, .lowConfidence:
                audioManager.playWarningSound()
            case .normal:
                break
            }
            
        case .hapticSpeech:
            let priority: SpeechPriority = state == .stop ? .high : .normal
            speechManager.speak(message, priority: priority)
        }
    }
}

// MARK: - DepthCaptureDelegate

extension SensePathViewModel: DepthCaptureDelegate {
    
    func depthCaptureManager(_ manager: DepthCaptureManager,
                            didOutput depthData: AVDepthData,
                            sampleBuffer: CMSampleBuffer) {
        processFrame(depthData: depthData, sampleBuffer: sampleBuffer)
    }
    
    func depthCaptureManager(_ manager: DepthCaptureManager,
                            didEncounterError error: CaptureError) {
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = error.localizedDescription
            self?.stop()
        }
    }
}
