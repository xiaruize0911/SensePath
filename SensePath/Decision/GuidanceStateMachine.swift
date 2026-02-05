//
//  GuidanceStateMachine.swift
//  SensePath
//
//  导航状态机 - 将深度信息转换为可行动的导航建议
//

import Foundation

// MARK: - State Definition

/// 导航状态
enum GuidanceState: Equatable {
    case normal             // 正常，无警告
    case warningLeft       // 建议向左移动
    case warningRight      // 建议向右移动
    case stop              // 停止前进
    case lowConfidence     // 深度数据不可靠
    
    var displayName: String {
        switch self {
        case .normal: return "正常"
        case .warningLeft: return "向左"
        case .warningRight: return "向右"
        case .stop: return "停止"
        case .lowConfidence: return "低可靠"
        }
    }
    
    var icon: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .warningLeft: return "arrow.left.circle.fill"
        case .warningRight: return "arrow.right.circle.fill"
        case .stop: return "hand.raised.fill"
        case .lowConfidence: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Output

/// 导航输出
struct GuidanceOutput {
    let state: GuidanceState
    let urgency: Float          // [0, 1] 紧迫度
    let stateChanged: Bool      // 状态是否变化
    let message: String?        // 语音消息（状态变化时）
    let debugInfo: String       // 调试信息
}

// MARK: - Configuration

struct GuidanceThresholds {
    var stopDistance: Float     // 停止距离（米）
    var warnDistance: Float     // 警告距离（米）
    var hysteresis: Float       // 滞后带（米），避免左右抖动
    
    static let `default` = GuidanceThresholds(
        stopDistance: 0.5,      // 缩小停止距离
        warnDistance: 1.0,      // 缩小警告范围，减少无端触发
        hysteresis: 0.25        // 增加滞后带，减少状态频繁切换
    )
    
    static let conservative = GuidanceThresholds(
        stopDistance: 0.8,
        warnDistance: 1.5,
        hysteresis: 0.2
    )
    
    static let aggressive = GuidanceThresholds(
        stopDistance: 0.4,
        warnDistance: 1.0,
        hysteresis: 0.1
    )
}

// MARK: - Main Class

class GuidanceStateMachine {
    
    // MARK: Properties
    
    var thresholds: GuidanceThresholds
    
    private(set) var currentState: GuidanceState = .normal
    private var stateEnterTime: Date?
    private let minStateDuration: TimeInterval = 0.5  // 增加到 0.5 秒，防止触觉因微小变化频繁震动
    
    // MARK: Initialization
    
    init(thresholds: GuidanceThresholds = .default) {
        self.thresholds = thresholds
    }
    
    // MARK: Public Methods
    
    /// 更新状态机
    func update(sectorDepth: SectorDepth, quality: DepthQualityMetrics) -> GuidanceOutput {
        let newState = determineState(sectorDepth: sectorDepth, quality: quality)
        let stateChanged = (newState != currentState)
        
        // 防抖：如果状态变化过快，延迟切换
        if stateChanged {
            if let enterTime = stateEnterTime,
               Date().timeIntervalSince(enterTime) < minStateDuration {
                // 保持当前状态
                return buildOutput(
                    state: currentState,
                    sectorDepth: sectorDepth,
                    stateChanged: false
                )
            }
            
            currentState = newState
            stateEnterTime = Date()
        }
        
        return buildOutput(
            state: currentState,
            sectorDepth: sectorDepth,
            stateChanged: stateChanged
        )
    }
    
    /// 重置状态机
    func reset() {
        currentState = .normal
        stateEnterTime = nil
    }
    
    // MARK: - Private Methods
    
    /// 决定新状态
    private func determineState(
        sectorDepth: SectorDepth,
        quality: DepthQualityMetrics
    ) -> GuidanceState {
        // 1. 检查停止条件 (最高优先级)
        if sectorDepth.center < thresholds.stopDistance {
            return .stop
        }

        // 2. 检查警告条件
        if sectorDepth.center < thresholds.warnDistance {
            // 比较左右，决定方向
            let leftClearance = sectorDepth.left - sectorDepth.right
            
            if leftClearance > thresholds.hysteresis {
                return .warningLeft
            } else if leftClearance < -thresholds.hysteresis {
                return .warningRight
            }
        }
        
        // 3. 检查质量 (仅当没有紧迫障碍物时才报告低可靠)
        if !quality.isReliable {
            return .lowConfidence
        }
        
        // 4. 正常状态
        return .normal
    }
    
    /// 构建输出
    private func buildOutput(
        state: GuidanceState,
        sectorDepth: SectorDepth,
        stateChanged: Bool
    ) -> GuidanceOutput {
        let urgency = calculateUrgency(state: state, centerDepth: sectorDepth.center)
        let message = stateChanged ? generateMessage(state: state) : nil
        let debugInfo = formatDebugInfo(sectorDepth: sectorDepth)
        
        return GuidanceOutput(
            state: state,
            urgency: urgency,
            stateChanged: stateChanged,
            message: message,
            debugInfo: debugInfo
        )
    }
    
    /// 计算紧迫度
    private func calculateUrgency(state: GuidanceState, centerDepth: Float) -> Float {
        switch state {
        case .stop:
            return 1.0
            
        case .warningLeft, .warningRight:
            // 从 warnDistance 到 stopDistance，urgency 从 0 到 1
            let range = thresholds.warnDistance - thresholds.stopDistance
            let normalized = (thresholds.warnDistance - centerDepth) / range
            return max(0, min(1, normalized))
            
        case .lowConfidence:
            return 0.3  // 低紧迫度，但需要注意
            
        case .normal:
            return 0.0
        }
    }
    
    /// 生成语音消息
    private func generateMessage(state: GuidanceState) -> String {
        switch state {
        case .stop:
            return "停止"
        case .warningLeft:
            return "向左移动"
        case .warningRight:
            return "向右移动"
        case .lowConfidence:
            return "深度不稳定，请放慢"
        case .normal:
            return "前方畅通"
        }
    }
    
    /// 格式化调试信息
    private func formatDebugInfo(sectorDepth: SectorDepth) -> String {
        return String(format: "L:%.2fm C:%.2fm R:%.2fm | 空洞:%.0f%% 抖动:%.2fm",
                     sectorDepth.left,
                     sectorDepth.center,
                     sectorDepth.right,
                     sectorDepth.invalidRatio * 100,
                     sectorDepth.stability)
    }
}
