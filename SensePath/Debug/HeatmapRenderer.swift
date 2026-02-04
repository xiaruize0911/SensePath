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
        
        // 2. 映射逻辑优化：使用 CIColorPolynomial 来处理 0 (无效/太远)
        // 我们希望 d=0 时不显示红色。
        // 多项式公式: r = a0 + a1*d + a2*d^2 + a3*d^3
        // 我们设 a0 = 0, 这样 d=0 时 r=0 (不显示红色)
        // 我们设 a1 = 2.0, a2 = -0.5, 这样在 1m 左右 R 达到峰值，在 4m 左右归零
        
        let polyFilter = CIFilter.colorPolynomial()
        polyFilter.inputImage = ciImage
        
        // R 通道: 处理危险区 (0.5m - 2.0m)
        // a0=0, a1=2.5, a2=-1.0 (在 1.25m 处达到峰值)
        polyFilter.redCoefficients = CIVector(x: 0, y: 2.5, z: -1.0, w: 0)
        
        // G 通道: 保持黑色
        polyFilter.greenCoefficients = CIVector(x: 0, y: 0, z: 0, w: 0)
        
        // B 通道: 随距离增加 (安全区)
        // a0=0, a1=0.2, a2=0.05
        polyFilter.blueCoefficients = CIVector(x: 0, y: 0.2, z: 0.05, w: 0)
        
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
