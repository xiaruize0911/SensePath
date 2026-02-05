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
        roiVerticalRange: 0.4...0.9,  // 略微上移 ROI，避免拍到手部或地面过近处
        percentile: 0.25,             // 提高分位数到 25%，显著降低对噪点和孤立像素的敏感度
        smoothingAlpha: 0.2,          // 更强的平滑 (Alpha 越小越平滑)
        stabilityWindow: 30,          // 增加窗口大小，增加平滑度
        invalidThreshold: 0.45,       // 允许 45% 的空洞（通常是因为物体太远）
        stabilityThreshold: 0.20,     // 允许 20cm 的抖动
        minFPS: 15.0,
        depthRange: 0.2...3.5         // 扩大检测范围到 3.5m
    )
}

// MARK: - Main Class

class DepthAnalyzer {
    
    // MARK: Properties
    
    var config: AnalyzerConfig
    
    // 平滑与稳定性追踪
    private var leftDepthHistory: [Float] = []
    private var centerDepthHistory: [Float] = []
    private var rightDepthHistory: [Float] = []
    
    private var smoothedLeftDepth: Float?
    private var smoothedCenterDepth: Float?
    private var smoothedRightDepth: Float?
    
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
        // 如果没有有效深度值，默认为无穷大
        let dL = percentile(of: leftValues, p: config.percentile) ?? Float.infinity
        let dC = percentile(of: centerValues, p: config.percentile) ?? Float.infinity
        let dR = percentile(of: rightValues, p: config.percentile) ?? Float.infinity
        
        // 5. 平滑所有扇区距离
        let sL = smoothDepth(dL, &smoothedLeftDepth, &leftDepthHistory)
        let sC = smoothDepth(dC, &smoothedCenterDepth, &centerDepthHistory)
        let sR = smoothDepth(dR, &smoothedRightDepth, &rightDepthHistory)
        
        // 6. 计算稳定性 (基于中心)
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
        // 统一处理无穷大为 10.0m，避免状态机溢出
        let sectorDepth = SectorDepth(
            left: sL.isFinite ? sL : 10.0,
            center: sC.isFinite ? sC : 10.0,
            right: sR.isFinite ? sR : 10.0,
            invalidRatio: invalidRatio,
            stability: stability
        )
        
        return (sectorDepth, quality)
    }
    
    /// 重置状态
    func reset() {
        leftDepthHistory.removeAll()
        centerDepthHistory.removeAll()
        rightDepthHistory.removeAll()
        
        smoothedLeftDepth = nil
        smoothedCenterDepth = nil
        smoothedRightDepth = nil
        
        consecutiveInvalidFrames = 0
    }
    
    // MARK: - Private Methods
    
    /// 转换深度数据为米制并统一为 Float32 格式
    private func convertToMeters(depthData: AVDepthData) -> CVPixelBuffer {
        let depthType = depthData.depthDataType
        
        // 如果已经是 Float32 深度图，直接返回
        if depthType == kCVPixelFormatType_DepthFloat32 {
            return depthData.depthDataMap
        }
        
        // 统一转换为 Float32 深度图 (Depth, 不是 Disparity)
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
    
    /// 通用平滑算法 (EMA)
    private func smoothDepth(_ rawValue: Float, _ smoothedValue: inout Float?, _ history: inout [Float]) -> Float {
        // 如果当前帧无效，尝试返回上一次的平滑值，如果没有上一次值则返回无穷大（表示远方）
        guard rawValue.isFinite else { return smoothedValue ?? Float.infinity }
        
        if let previous = smoothedValue {
            let alpha = config.smoothingAlpha
            smoothedValue = alpha * rawValue + (1 - alpha) * previous
        } else {
            smoothedValue = rawValue
        }
        
        // 更新历史记录（用于稳定性计算，主要关注中心扇区）
        history.append(smoothedValue!)
        if history.count > config.stabilityWindow {
            history.removeFirst()
        }
        
        return smoothedValue!
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
