//
//  DepthCaptureManager.swift
//  SensePath
//
//  深度采集管理器 - 配置 AVCaptureSession 并同步视频/深度数据流
//

import AVFoundation
import UIKit

// MARK: - Delegate Protocol

protocol DepthCaptureDelegate: AnyObject {
    func depthCaptureManager(_ manager: DepthCaptureManager,
                            didOutput depthData: AVDepthData,
                            sampleBuffer: CMSampleBuffer)
    func depthCaptureManager(_ manager: DepthCaptureManager,
                            didEncounterError error: CaptureError)
}

// MARK: - Error Types

enum CaptureError: Error, LocalizedError {
    case deviceNotAvailable
    case configurationFailed(String)
    case depthNotSupported
    case authorizationDenied
    
    var errorDescription: String? {
        switch self {
        case .deviceNotAvailable:
            return "TrueDepth 相机不可用"
        case .configurationFailed(let reason):
            return "配置失败: \(reason)"
        case .depthNotSupported:
            return "此设备不支持深度数据"
        case .authorizationDenied:
            return "相机权限被拒绝"
        }
    }
}

// MARK: - Main Class

class DepthCaptureManager: NSObject {
    
    // MARK: Properties
    
    weak var delegate: DepthCaptureDelegate?
    
    private let session = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let depthDataOutput = AVCaptureDepthDataOutput()
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    
    private let sessionQueue = DispatchQueue(label: "com.sensepath.capture.session")
    private let dataOutputQueue = DispatchQueue(label: "com.sensepath.capture.data",
                                                qos: .userInitiated)
    
    private(set) var isRunning = false
    private(set) var currentFPS: Double = 0
    private var frameCount = 0
    private var lastFPSUpdate = Date()
    
    // MARK: - Lifecycle
    
    deinit {
        stopCapture()
    }
    
    // MARK: - Public Methods
    
    /// 检查设备是否支持深度数据
    func isDepthAvailable() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInTrueDepthCamera,
                                                   for: .video,
                                                   position: .front) else {
            return false
        }
        
        return !device.activeFormat.supportedDepthDataFormats.isEmpty
    }
    
    /// 启动采集
    func startCapture() throws {
        try sessionQueue.sync {
            try self.setupSession()
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
                DispatchQueue.main.async {
                    self?.isRunning = true
                }
            }
        }
    }
    
    /// 停止采集
    func stopCapture() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.session.isRunning {
                self.session.stopRunning()
            }
            
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }
    
    // MARK: - Private Setup
    
    private func setupSession() throws {
        // 1. 检查权限
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            // 同步请求权限（仅用于演示，实际应在 UI 层异步处理）
            var granted = false
            let semaphore = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .video) { success in
                granted = success
                semaphore.signal()
            }
            semaphore.wait()
            if !granted {
                throw CaptureError.authorizationDenied
            }
        default:
            throw CaptureError.authorizationDenied
        }
        
        // 2. 获取 TrueDepth 相机
        guard let videoDevice = AVCaptureDevice.default(.builtInTrueDepthCamera,
                                                        for: .video,
                                                        position: .front) else {
            throw CaptureError.deviceNotAvailable
        }
        
        // 3. 选择支持深度的格式
        let depthFormats = videoDevice.activeFormat.supportedDepthDataFormats
        guard !depthFormats.isEmpty else {
            throw CaptureError.depthNotSupported
        }
        
        // 优先选择 depth（米制）而非 disparity
        let selectedDepthFormat = depthFormats.first { format in
            let pixelFormatType = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            return pixelFormatType == kCVPixelFormatType_DepthFloat32
        } ?? depthFormats.first!
        
        // 4. 配置设备
        try videoDevice.lockForConfiguration()
        videoDevice.activeDepthDataFormat = selectedDepthFormat
        videoDevice.unlockForConfiguration()
        
        // 5. 创建输入
        let deviceInput = try AVCaptureDeviceInput(device: videoDevice)
        
        // 6. 配置会话
        session.beginConfiguration()
        session.sessionPreset = .vga640x480  // 平衡性能和质量
        
        // 添加输入
        if session.canAddInput(deviceInput) {
            session.addInput(deviceInput)
            videoDeviceInput = deviceInput
        } else {
            session.commitConfiguration()
            throw CaptureError.configurationFailed("无法添加视频输入")
        }
        
        // 添加视频输出
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        } else {
            session.commitConfiguration()
            throw CaptureError.configurationFailed("无法添加视频输出")
        }
        
        // 添加深度输出
        depthDataOutput.isFilteringEnabled = true  // 启用深度平滑
        depthDataOutput.alwaysDiscardsLateDepthData = true
        
        if session.canAddOutput(depthDataOutput) {
            session.addOutput(depthDataOutput)
        } else {
            session.commitConfiguration()
            throw CaptureError.configurationFailed("无法添加深度输出")
        }
        
        // 7. 配置同步器
        guard let videoConnection = videoDataOutput.connection(with: .video),
              let depthConnection = depthDataOutput.connection(with: .depthData) else {
            session.commitConfiguration()
            throw CaptureError.configurationFailed("无法建立连接")
        }
        
        // 设置方向（前置摄像头，镜像）
        if videoConnection.isVideoMirroringSupported {
            videoConnection.isVideoMirrored = true
        }
        
        if depthConnection.isVideoMirroringSupported {
            depthConnection.isVideoMirrored = true
        }
        
        let synchronizer = AVCaptureDataOutputSynchronizer(
            dataOutputs: [videoDataOutput, depthDataOutput]
        )
        synchronizer.setDelegate(self, queue: dataOutputQueue)
        outputSynchronizer = synchronizer
        
        session.commitConfiguration()
    }
    
    // MARK: - FPS Tracking
    
    private func updateFPS() {
        frameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFPSUpdate)
        
        if elapsed >= 1.0 {
            currentFPS = Double(frameCount) / elapsed
            frameCount = 0
            lastFPSUpdate = now
        }
    }
}

// MARK: - AVCaptureDataOutputSynchronizerDelegate

extension DepthCaptureManager: AVCaptureDataOutputSynchronizerDelegate {
    
    func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        // 获取同步的视频和深度数据
        guard let syncedDepthData = synchronizedDataCollection.synchronizedData(
                for: depthDataOutput) as? AVCaptureSynchronizedDepthData,
              let syncedVideoData = synchronizedDataCollection.synchronizedData(
                for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData else {
            return
        }
        
        // 检查深度数据是否被丢弃
        if syncedDepthData.depthDataWasDropped || syncedVideoData.sampleBufferWasDropped {
            return
        }
        
        let depthData = syncedDepthData.depthData
        let sampleBuffer = syncedVideoData.sampleBuffer
        
        // 更新 FPS
        updateFPS()
        
        // 回调到代理
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.depthCaptureManager(self,
                                              didOutput: depthData,
                                              sampleBuffer: sampleBuffer)
        }
    }
}
