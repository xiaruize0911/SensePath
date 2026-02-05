//
//  SettingsView.swift
//  SensePath
//
//  设置界面 - 完整无障碍支持
//

import SwiftUI

struct SettingsView: View {
    
    @ObservedObject var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                // MARK: - 距离阈值
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("停止距离: \(String(format: "%.1f", settings.stopThreshold))m")
                            .accessibilityLabel("停止距离")
                            .accessibilityValue("\(String(format: "%.1f", settings.stopThreshold)) 米")
                        
                        Slider(value: $settings.stopThreshold, in: 0.3...1.0, step: 0.1)
                            .accessibilityLabel("调整停止距离")
                            .accessibilityHint("滑动以设置检测到障碍物时停止的距离")
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("警告距离: \(String(format: "%.1f", settings.warnThreshold))m")
                            .accessibilityLabel("警告距离")
                            .accessibilityValue("\(String(format: "%.1f", settings.warnThreshold)) 米")
                        
                        Slider(value: $settings.warnThreshold, in: 0.8...2.0, step: 0.1)
                            .accessibilityLabel("调整警告距离")
                            .accessibilityHint("滑动以设置开始警告的距离")
                    }
                } header: {
                    Text("距离阈值")
                        .accessibilityAddTraits(.isHeader)
                } footer: {
                    Text("停止距离：小于此距离时发出停止信号\n警告距离：小于此距离时开始方向引导")
                }
                
                // MARK: - 输出模式
                Section {
                    Picker("输出模式", selection: $settings.outputMode) {
                        ForEach(OutputMode.allCases, id: \.self) { mode in
                            Text(mode.description)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("选择输出模式")
                    .accessibilityHint("选择反馈方式：仅触觉、触觉加提示音、或触觉加语音")
                } header: {
                    Text("反馈方式")
                        .accessibilityAddTraits(.isHeader)
                } footer: {
                    Text(outputModeDescription)
                }
                
                // MARK: - 灵敏度
                Section {
                    Picker("灵敏度", selection: $settings.sensitivity) {
                        ForEach(Sensitivity.allCases, id: \.self) { sens in
                            Text(sens.description)
                                .tag(sens)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("选择灵敏度")
                    .accessibilityHint("选择检测灵敏度级别")
                } header: {
                    Text("灵敏度")
                        .accessibilityAddTraits(.isHeader)
                } footer: {
                    Text(sensitivityDescription)
                }
                
                // MARK: - 调试选项
                Section {
                    Toggle("调试模式", isOn: $settings.debugMode)
                        .accessibilityLabel("调试模式")
                        .accessibilityHint(settings.debugMode ? "已开启，显示调试信息" : "已关闭")
                    
                    Toggle("显示数值", isOn: $settings.showMetrics)
                        .accessibilityLabel("显示距离数值")
                        .accessibilityHint(settings.showMetrics ? "已开启，显示详细距离数据" : "已关闭")
                    
                    Toggle("记录日志", isOn: $settings.enableLogging)
                        .accessibilityLabel("记录日志")
                        .accessibilityHint(settings.enableLogging ? "已开启，记录运行日志" : "已关闭")
                    
                    if settings.enableLogging {
                        TextField("监控服务器 URL", text: $settings.remoteLogURL)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                            .accessibilityLabel("记录日志服务器地址")
                    }
                } header: {
                    Text("调试选项")
                        .accessibilityAddTraits(.isHeader)
                } footer: {
                    Text("日志可以发送到 Mac 上的监控网页")
                }
                
                // MARK: - 重置按钮
                Section {
                    Button(role: .destructive) {
                        settings.reset()
                    } label: {
                        HStack {
                            Spacer()
                            Text("恢复默认设置")
                            Spacer()
                        }
                    }
                    .accessibilityLabel("恢复默认设置")
                    .accessibilityHint("将所有设置恢复到出厂默认值")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .accessibilityLabel("完成")
                    .accessibilityHint("关闭设置页面")
                }
            }
        }
    }
    
    // MARK: - Computed Descriptions
    
    private var outputModeDescription: String {
        switch settings.outputMode {
        case .hapticOnly:
            return "仅使用触觉反馈，适合安静环境"
        case .hapticBeep:
            return "触觉 + 提示音，适合需要音频提示但不需要语音的场景"
        case .hapticSpeech:
            return "触觉 + 语音播报，推荐盲人用户使用"
        }
    }
    
    private var sensitivityDescription: String {
        switch settings.sensitivity {
        case .low:
            return "低灵敏度：更保守的检测，减少误报，适合初学者"
        case .medium:
            return "中等灵敏度：平衡的检测策略，推荐日常使用"
        case .high:
            return "高灵敏度：更激进的检测，快速响应，适合熟练用户"
        }
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settings: SettingsManager())
    }
}
