//
//  SensePathApp.swift
//  SensePath
//
//  应用入口
//

import SwiftUI

@main
struct SensePathApp: App {
    
    init() {
        // 配置全局无障碍
        UIAccessibility.post(notification: .announcement, argument: "SensePath 声路已启动")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)  // 使用深色主题
        }
    }
}
