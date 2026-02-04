//
//  ContentView.swift
//  SensePath
//
//  主界面 - 带完整无障碍支持的主控制界面
//

import SwiftUI

struct ContentView: View {
    
    @StateObject private var settings = SettingsManager()
    @StateObject private var viewModel: SensePathViewModel
    @State private var showSettings = false
    
    init() {
        let settings = SettingsManager()
        _settings = StateObject(wrappedValue: settings)
        _viewModel = StateObject(wrappedValue: SensePathViewModel(settings: settings))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // 背景色根据状态变化
                stateBackgroundColor
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.3), value: viewModel.currentState)
                
                ScrollView {
                    VStack(spacing: 20) {
                        
                        // 标题
                        VStack(spacing: 4) {
                            Text("SensePath")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Text("声路")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.top, 20)
                        .accessibilityAddTraits(.isHeader)
                        
                        // 状态显示
                        StateIndicatorView(
                            state: viewModel.currentState,
                            urgency: viewModel.urgency
                        )
                        .frame(height: 180)
                        
                        // 主按钮
                        MainControlButton(
                            isRunning: viewModel.isRunning,
                            action: {
                                if viewModel.isRunning {
                                    viewModel.stop()
                                } else {
                                    viewModel.start()
                                }
                            }
                        )
                        
                        // FPS 指示
                        if viewModel.isRunning {
                            Text("FPS: \(Int(viewModel.fps))")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        // 调试图
                        if settings.showMetrics && viewModel.isRunning {
                            VStack(spacing: 12) {
                                HStack(spacing: 10) {
                                    if let original = viewModel.originalImage {
                                        DebugImageView(image: original, label: "原始图像")
                                    } else {
                                        placeholderView("等待画面...")
                                    }
                                    
                                    if let heatmap = viewModel.heatmapImage {
                                        DebugImageView(image: heatmap, label: "深度热力图")
                                    } else {
                                        placeholderView("等待深度...")
                                    }
                                }
                                
                                MetricsView(
                                    left: viewModel.leftDistance,
                                    center: viewModel.centerDistance,
                                    right: viewModel.rightDistance,
                                    invalidRatio: viewModel.invalidRatio,
                                    stability: viewModel.stability
                                )
                            }
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(16)
                        }
                        
                        // 错误提示
                        if let error = viewModel.errorMessage {
                            ErrorBanner(message: error)
                        }
                        
                        Spacer(minLength: 50)
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .accessibilityLabel("设置")
                    .accessibilityHint("打开设置界面")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: settings)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var stateBackgroundColor: Color {
        switch viewModel.currentState {
        case .normal:
            return Color.green.opacity(0.3)
        case .warningLeft, .warningRight:
            return Color.orange.opacity(0.3 + Double(viewModel.urgency) * 0.4)
        case .stop:
            return Color.red.opacity(0.6)
        case .lowConfidence:
            return Color.gray.opacity(0.5)
        }
    }
}

// MARK: - State Indicator

struct StateIndicatorView: View {
    let state: GuidanceState
    let urgency: Float
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: state.icon)
                .font(.system(size: 80))
                .foregroundColor(.white)
                .accessibilityHidden(true)
            
            Text(state.displayName)
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.white)
            
            if urgency > 0 {
                ProgressView(value: Double(urgency))
                    .progressViewStyle(LinearProgressViewStyle(tint: .white))
                    .frame(width: 200)
                    .accessibilityLabel("紧迫度")
                    .accessibilityValue("\(Int(urgency * 100))%")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前状态: \(state.displayName)")
        .accessibilityValue(urgency > 0 ? "紧迫度 \(Int(urgency * 100))%" : "")
    }
}

// MARK: - Main Control Button

struct MainControlButton: View {
    let isRunning: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRunning ? Color.red : Color.green)
                    .frame(width: 180, height: 180)
                    .shadow(radius: 10)
                
                VStack(spacing: 8) {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 50))
                    
                    Text(isRunning ? "停止" : "开始")
                        .font(.system(size: 24, weight: .bold))
                }
                .foregroundColor(.white)
            }
        }
        .accessibilityLabel(isRunning ? "停止避障" : "开始避障")
        .accessibilityHint(isRunning ? "点击停止实时避障检测" : "点击开始实时避障检测")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Debug Image View

struct DebugImageView: View {
    let image: UIImage
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 150, height: 200)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
            
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
        }
        .accessibilityLabel(label)
    }
}

func placeholderView(_ text: String) -> some View {
    VStack(spacing: 4) {
        Rectangle()
            .fill(Color.black.opacity(0.2))
            .frame(width: 150, height: 200)
            .cornerRadius(8)
            .overlay(
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            )
        
        Text("加载中")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white.opacity(0.7))
    }
}

// MARK: - Metrics View

struct MetricsView: View {
    let left: Float
    let center: Float
    let right: Float
    let invalidRatio: Float
    let stability: Float
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 20) {
                metricItem("左", left)
                metricItem("中", center)
                metricItem("右", right)
            }
            
            HStack(spacing: 20) {
                Text("空洞: \(Int(invalidRatio * 100))%")
                Text("抖动: \(Int(stability * 100))cm")
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white.opacity(0.8))
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("深度指标")
        .accessibilityValue("左侧 \(String(format: "%.1f", left)) 米, 中间 \(String(format: "%.1f", center)) 米, 右侧 \(String(format: "%.1f", right)) 米")
    }
    
    private func metricItem(_ label: String, _ value: Float) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
            Text(String(format: "%.2fm", value))
                .font(.system(size: 18, weight: .bold))
        }
        .foregroundColor(.white)
        .frame(width: 70)
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.8))
            .cornerRadius(12)
            .accessibilityLabel("错误")
            .accessibilityValue(message)
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
