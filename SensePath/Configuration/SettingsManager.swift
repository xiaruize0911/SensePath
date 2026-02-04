//
//  SettingsManager.swift
//  SensePath
//
//  设置管理器 - 管理用户配置并持久化
//

import Foundation
import Combine

// MARK: - Output Mode

enum OutputMode: String, CaseIterable, Codable {
    case hapticOnly = "仅触觉"
    case hapticBeep = "触觉+提示音"
    case hapticSpeech = "触觉+语音"
    
    var description: String { rawValue }
}

// MARK: - Sensitivity

enum Sensitivity: String, CaseIterable, Codable {
    case low = "低"
    case medium = "中"
    case high = "高"
    
    var description: String { rawValue }
    
    var analyzerConfig: AnalyzerConfig {
        switch self {
        case .low:
            return AnalyzerConfig(
                roiVerticalRange: 0.5...1.0,
                percentile: 0.15,  // 更保守
                smoothingAlpha: 0.2,  // 更强平滑
                stabilityWindow: 30,
                invalidThreshold: 0.3,
                stabilityThreshold: 0.15,
                minFPS: 20.0,
                depthRange: 0.2...2.0
            )
            
        case .medium:
            return .default
            
        case .high:
            return AnalyzerConfig(
                roiVerticalRange: 0.5...1.0,
                percentile: 0.08,  // 更激进
                smoothingAlpha: 0.4,  // 更弱平滑
                stabilityWindow: 15,
                invalidThreshold: 0.2,
                stabilityThreshold: 0.10,
                minFPS: 20.0,
                depthRange: 0.2...2.0
            )
        }
    }
    
    var guidanceThresholds: GuidanceThresholds {
        switch self {
        case .low:
            return .conservative
        case .medium:
            return .default
        case .high:
            return .aggressive
        }
    }
}

// MARK: - Main Class

class SettingsManager: ObservableObject {
    
    // MARK: Published Properties
    
    @Published var stopThreshold: Float {
        didSet { save() }
    }
    
    @Published var warnThreshold: Float {
        didSet { save() }
    }
    
    @Published var outputMode: OutputMode {
        didSet { save() }
    }
    
    @Published var sensitivity: Sensitivity {
        didSet { save() }
    }
    
    @Published var debugMode: Bool {
        didSet { save() }
    }
    
    @Published var showMetrics: Bool {
        didSet { save() }
    }
    
    @Published var enableLogging: Bool {
        didSet { save() }
    }
    
    // MARK: Constants
    
    private enum Keys {
        static let stopThreshold = "stopThreshold"
        static let warnThreshold = "warnThreshold"
        static let outputMode = "outputMode"
        static let sensitivity = "sensitivity"
        static let debugMode = "debugMode"
        static let showMetrics = "showMetrics"
        static let enableLogging = "enableLogging"
    }
    
    private let defaults = UserDefaults.standard
    
    // MARK: Initialization
    
    init() {
        // 加载或使用默认值
        self.stopThreshold = defaults.object(forKey: Keys.stopThreshold) as? Float ?? 0.6
        self.warnThreshold = defaults.object(forKey: Keys.warnThreshold) as? Float ?? 1.2
        
        if let modeString = defaults.string(forKey: Keys.outputMode),
           let mode = OutputMode(rawValue: modeString) {
            self.outputMode = mode
        } else {
            self.outputMode = .hapticSpeech
        }
        
        if let sensString = defaults.string(forKey: Keys.sensitivity),
           let sens = Sensitivity(rawValue: sensString) {
            self.sensitivity = sens
        } else {
            self.sensitivity = .medium
        }
        
        self.debugMode = defaults.bool(forKey: Keys.debugMode)
        self.showMetrics = defaults.bool(forKey: Keys.showMetrics)
        self.enableLogging = defaults.bool(forKey: Keys.enableLogging)
    }
    
    // MARK: Public Methods
    
    func save() {
        defaults.set(stopThreshold, forKey: Keys.stopThreshold)
        defaults.set(warnThreshold, forKey: Keys.warnThreshold)
        defaults.set(outputMode.rawValue, forKey: Keys.outputMode)
        defaults.set(sensitivity.rawValue, forKey: Keys.sensitivity)
        defaults.set(debugMode, forKey: Keys.debugMode)
        defaults.set(showMetrics, forKey: Keys.showMetrics)
        defaults.set(enableLogging, forKey: Keys.enableLogging)
    }
    
    func reset() {
        stopThreshold = 0.6
        warnThreshold = 1.2
        outputMode = .hapticSpeech
        sensitivity = .medium
        debugMode = false
        showMetrics = false
        enableLogging = false
    }
    
    // MARK: Computed Properties
    
    var currentGuidanceThresholds: GuidanceThresholds {
        var thresholds = sensitivity.guidanceThresholds
        thresholds = GuidanceThresholds(
            stopDistance: stopThreshold,
            warnDistance: warnThreshold,
            hysteresis: thresholds.hysteresis
        )
        return thresholds
    }
    
    var currentAnalyzerConfig: AnalyzerConfig {
        return sensitivity.analyzerConfig
    }
}
