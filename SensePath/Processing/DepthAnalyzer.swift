//
//  DepthAnalyzer.swift
//  SensePath
//
//  深度分析器 - 将深度图转换为左/中/右扇区的障碍距离信息
//

import AVFoundation
import Accelerate
import CoreVideo

// MARK: - Data Models

/// 三扇区深度信息
struct SectorDepth {
    let left: Float         // dL: 左扇区最近距离（米）
    let center: Float       // dC: 中间扇区最近距离（米）
    let right: Float        // dR: 右扇区最近距离（米）
    let invalidRatio: Float // 整体空洞率 [0, 1]
    let stability: Float    // dC 的时域稳定性（标准差）
    
    var isValid: Bool {
        left > 0 && center > 0 && right > 0
    }
}

/// 深度质量评估
struct DepthQualityMetrics {
    let isReliable: Bool    // 是否可信
    let invalidRatio: Float // 空洞率
    let temporalStability: Float // 时域稳定性
    let fps: Double         // 当前帧率
    let reason: String?     // 不可信时的原因
}

// MARK: - Configuration

struct AnalyzerConfig {
    /// ROI 垂直范围（归一化坐标，0=顶部，1=底部）
    let roiVerticalRange: ClosedRange<Float>
    
    /// 分位数（用于计算扇区最近距离，抗噪）
    let percentile: Float
    
    /// EMA 平滑系数
    let smoothingAlpha: Float
    
    /// 稳定性计算窗口（帧数）
    let stabilityWindow: Int
    
    /// 空洞率阈值
    let invalidThreshold: Float
    
    /// 稳定性阈值（米）
    let stabilityThreshold: Float
    
    /// 最小 FPS 要求
    let minFPS: Double
    
    /// 深度有效范围（米）
    let depthRange: ClosedRange<Float>
    
    static let `default` = AnalyzerConfig(
        roiVerticalRange: 0.5...1.0,  // 画面下半部
        percentile: 0.1,              // 10th percentile
        smoothingAlpha: 0.3,          // 较强平滑
        stabilityWindow: 20,          // 20 帧约 0.67 秒
        invalidThreshold: 0.25,       // 25% 空洞
        stabilityThreshold: 0.12,     // 12cm 抖动
        minFPS: 20.0,
        depthRange: 0.2...2.0         // TrueDepth 有效范围
    )
}

// MARK: - Main Class

class DepthAnalyzer {
    
    // MARK: Properties
    
    var config: AnalyzerConfig
    
    // 平滑与稳定性追踪
    private var centerDepthHistory: [Float] = []
    private var smoothedCenterDepth: Float?
    private var consecutiveInvalidFrames = 0
    
    // MARK: Initialization
    
    init(config: AnalyzerConfig = .default) {
        self.config = config
    }
    
    // MARK: Public Methods
    
    /// 分析深度数据，返回扇区信息和质量评估
    func analyze(depthData: AVDepthData, fps: Double) -> (SectorDepth, DepthQualityMetrics) {
        // 1. 获取深度图
        let depthMap = depthData.depthDataMap
        
        // 2. 转换为米制（如果需要）
        let depthInMeters = convertToMeters(depthData: depthData)
        
        // 3. 提取 ROI 并切分为三个扇区
        let (leftValues, centerValues, rightValues, totalInvalid, totalPixels) = extractSectors(
            from: depthInMeters
        )
        
        // 4. 计算每个扇区的最近距离（分位数）
        let dL = percentile(of: leftValues, p: config.percentile) ?? Float.infinity
        let dC = percentile(of: centerValues, p: config.percentile) ?? Float.infinity
        let dR = percentile(of: rightValues, p: config.percentile) ?? Float.infinity
        
        // 5. 平滑中心距离
        let smoothedDC = smoothCenterDepth(dC)
        
        // 6. 计算稳定性
        let stability = calculateStability()
        
        // 7. 计算空洞率
        let invalidRatio = Float(totalInvalid) / Float(totalPixels)
        
        // 8. 质量评估
        let quality = assessQuality(
            invalidRatio: invalidRatio,
            stability: stability,
            fps: fps,
            hasValidDepth: dC.isFinite
        )
        
        // 9. 构造结果
        let sectorDepth = SectorDepth(
            left: dL.isFinite ? dL : 0,
            center: smoothedDC.isFinite ? smoothedDC : 0,
            right: dR.isFinite ? dR : 0,
            invalidRatio: invalidRatio,
            stability: stability
        )
        
        return (sectorDepth, quality)
    }
    
    /// 重置状态
    func reset() {
        centerDepthHistory.removeAll()
        smoothedCenterDepth = nil
        consecutiveInvalidFrames = 0
    }
    
    // MARK: - Private Methods
    
    /// 转换深度数据为米制
    private func convertToMeters(depthData: AVDepthData) -> CVPixelBuffer {
        let depthType = depthData.depthDataType
        
        // 如果已经是深度（米），直接返回
        if depthType == kCVPixelFormatType_DepthFloat32 ||
           depthType == kCVPixelFormatType_DepthFloat16 {
            return depthData.depthDataMap
        }
        
        // 否则从视差转换（disparity -> depth）
        // depth = 1 / disparity
        return depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32).depthDataMap
    }
    
    /// 提取 ROI 并切分为左/中/右三个扇区
    private func extractSectors(from depthMap: CVPixelBuffer) -> (
        left: [Float],
        center: [Float],
        right: [Float],
        invalidCount: Int,
        totalCount: Int
    ) {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return ([], [], [], 0, 0)
        }
        
        // 计算 ROI 范围
        let startY = Int(Float(height) * config.roiVerticalRange.lowerBound)
        let endY = Int(Float(height) * config.roiVerticalRange.upperBound)
        
        // 三等分宽度
        let sectorWidth = width / 3
        let leftRange = 0..<sectorWidth
        let centerRange = sectorWidth..<(2 * sectorWidth)
        let rightRange = (2 * sectorWidth)..<width
        
        var leftValues: [Float] = []
        var centerValues: [Float] = []
        var rightValues: [Float] = []
        var invalidCount = 0
        var totalCount = 0
        
        // 遍历 ROI
        for y in startY..<endY {
            let rowData = baseAddress.advanced(by: y * bytesPerRow)
                .assumingMemoryBound(to: Float32.self)
            
            for x in 0..<width {
                let depth = rowData[x]
                totalCount += 1
                
                // 验证深度值
                if !depth.isFinite ||
                   depth <= 0 ||
                   !config.depthRange.contains(depth) {
                    invalidCount += 1
                    continue
                }
                
                // 分配到扇区
                if leftRange.contains(x) {
                    leftValues.append(depth)
                } else if centerRange.contains(x) {
                    centerValues.append(depth)
                } else if rightRange.contains(x) {
                    rightValues.append(depth)
                }
            }
        }
        
        return (leftValues, centerValues, rightValues, invalidCount, totalCount)
    }
    
    /// 计算分位数（使用 Accelerate）
    private func percentile(of values: [Float], p: Float) -> Float? {
        guard !values.isEmpty else { return nil }
        
        var sortedValues = values.sorted()
        let index = Int(Float(sortedValues.count) * p)
        let clampedIndex = min(max(index, 0), sortedValues.count - 1)
        
        return sortedValues[clampedIndex]
    }
    
    /// 平滑中心深度（EMA）
    private func smoothCenterDepth(_ rawDC: Float) -> Float {
        guard rawDC.isFinite else { return smoothedCenterDepth ?? 0 }
        
        if let previous = smoothedCenterDepth {
            let alpha = config.smoothingAlpha
            smoothedCenterDepth = alpha * rawDC + (1 - alpha) * previous
        } else {
            smoothedCenterDepth = rawDC
        }
        
        // 更新历史记录
        centerDepthHistory.append(smoothedCenterDepth!)
        if centerDepthHistory.count > config.stabilityWindow {
            centerDepthHistory.removeFirst()
        }
        
        return smoothedCenterDepth!
    }
    
    /// 计算稳定性（标准差）
    private func calculateStability() -> Float {
        guard centerDepthHistory.count >= 10 else {
            return 0  // 数据不足，假设稳定
        }
        
        let values = centerDepthHistory
        let mean = values.reduce(0, +) / Float(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Float(values.count)
        
        return sqrt(variance)
    }
    
    /// 评估深度质量
    private func assessQuality(
        invalidRatio: Float,
        stability: Float,
        fps: Double,
        hasValidDepth: Bool
    ) -> DepthQualityMetrics {
        var reasons: [String] = []
        
        // 检查无效帧
        if !hasValidDepth {
            consecutiveInvalidFrames += 1
        } else {
            consecutiveInvalidFrames = 0
        }
        
        // 判定条件
        var isReliable = true
        
        if invalidRatio > config.invalidThreshold {
            isReliable = false
            reasons.append("空洞率过高(\(Int(invalidRatio * 100))%)")
        }
        
        if stability > config.stabilityThreshold {
            isReliable = false
            reasons.append("抖动过大(\(Int(stability * 100))cm)")
        }
        
        if fps < config.minFPS {
            isReliable = false
            reasons.append("帧率过低(\(Int(fps))fps)")
        }
        
        if consecutiveInvalidFrames > 5 {
            isReliable = false
            reasons.append("连续无效帧")
        }
        
        return DepthQualityMetrics(
            isReliable: isReliable,
            invalidRatio: invalidRatio,
            temporalStability: stability,
            fps: fps,
            reason: isReliable ? nil : reasons.joined(separator: ", ")
        )
    }
}
