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
    func render(depthBuffer: CVPixelBuffer, minDistance: Float, maxDistance: Float) -> UIImage? {
        // 1. 创建 CIImage
        let ciImage = CIImage(cvPixelBuffer: depthBuffer)
        
        // 2. 预处理：将深度值归一化并反转，使得近处为 1.0，远处为 0.0
        // 公式: normalized = (max - d) / (max - min)
        // normalized = d * (-1/(max-min)) + (max/(max-min))
        let diff = maxDistance - minDistance
        let scale = -1.0 / CGFloat(diff)
        let bias = CGFloat(maxDistance) / CGFloat(diff)
        
        // 使用 colorMatrix 进行缩放和偏移
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = ciImage
        colorMatrix.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
        colorMatrix.gVector = CIVector(x: scale, y: 0, z: 0, w: 0)
        colorMatrix.bVector = CIVector(x: scale, y: 0, z: 0, w: 0)
        colorMatrix.biasVector = CIVector(x: bias, y: bias, z: bias, w: 0)
        
        guard let matrixOutput = colorMatrix.outputImage else { return nil }
        
        // 2.5 限制范围在 [0, 1]，防止 NaN 或超出范围的值导致颜色异常
        let clampFilter = CIFilter.colorClamp()
        clampFilter.inputImage = matrixOutput
        clampFilter.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clampFilter.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        
        guard let normalizedImage = clampFilter.outputImage else { return nil }
        
        // 3. 应用伪彩色映射
        // 输入 x 在 [0, 1] 之间，1.0 代表极近 (minDistance)，0.0 代表远 (maxDistance)
        let polyFilter = CIFilter.colorPolynomial()
        polyFilter.inputImage = normalizedImage
        
        // R 通道: 危险区 (极近 x > 0.8)
        // 使用高次幂以确保险峰值在 1.0 附近且下降极快，减少重叠
        // 10x - 8 -> 0 at 0.8, 2 at 1.0
        polyFilter.redCoefficients = CIVector(x: -8.0, y: 10.0, z: 0, w: 0)
        
        // G 通道: 保持黑色
        polyFilter.greenCoefficients = CIVector(x: 0, y: 0, z: 0, w: 0)
        
        // B 通道: 警告区 (中近 0.4 < x < 0.7)
        // 开口向下的抛物线，顶点在 0.55
        // -40(x-0.4)(x-0.7) = -40(x^2 - 1.1x + 0.28) = -40x^2 + 44x - 11.2
        polyFilter.blueCoefficients = CIVector(x: -11.2, y: 44.0, z: -40.0, w: 0)
        
        // A 通道: 保持不透明
        polyFilter.alphaCoefficients = CIVector(x: 1, y: 0, z: 0, w: 0)
        
        guard let outputImage = polyFilter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: ciImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    /// 将普通采集 PixelBuffer 转换为 UIImage
    func convert(pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
