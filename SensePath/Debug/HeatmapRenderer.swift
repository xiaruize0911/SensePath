//
//  HeatmapRenderer.swift
//  SensePath
//
//  调试热力图渲染器 - 将深度数据映射为伪彩色图像，仅用于调试可视化
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

class HeatmapRenderer {
    
    private let context = CIContext()
    private let colorFilter = CIFilter.colorMatrix()
    
    /// 将深度 CVPixelBuffer 转换为热力图 UIImage
    /// - Parameters:
    ///   - depthBuffer: 深度图（Float32）
    ///   - minDistance: 映射最小值（米）
    ///   - maxDistance: 映射最大值（米）
    func render(depthBuffer: CVPixelBuffer, minDistance: Float, maxDistance: Float) -> UIImage? {
        // 1. 创建 CIImage
        let ciImage = CIImage(cvPixelBuffer: depthBuffer)
        
        // 2. 映射范围：将 [min, max] 映射到 [0, 1]
        // 这里通过色彩矩阵简单模拟：近处(红色) -> 远处(蓝色)
        // 实际上完整的热力图通常使用自定义 Metal Shader 或 CIColorCube
        
        // 简单映射逻辑：
        // 深度越大 -> 蓝色越强
        // 深度越小 -> 红色越强
        
        // 我们这里使用一个简单的卷积或者色彩映射滤镜
        // 注意：深度图是单通道 Float32
        
        let range = maxDistance - minDistance
        
        // 使用 CIColorMatrix 调整通道（简单近似）
        let filter = CIFilter.colorMatrix()
        filter.inputImage = ciImage
        // 将红色通道设为 1/depth（反比），蓝色通道设为 depth
        filter.rVector = CIVector(x: -1.0 / CGFloat(range), y: 0, z: 0, w: 1.0)
        filter.bVector = CIVector(x: 1.0 / CGFloat(range), y: 0, z: 0, w: 0)
        
        guard let outputImage = filter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
}
