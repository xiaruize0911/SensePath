//
//  RemoteLogger.swift
//  SensePath
//
//  远程日志器 - 将实时调试信息传输到 Mac 上的监控网页
//

import Foundation

struct RemoteLogPayload: Codable {
    let state: String
    let left: Float
    let center: Float
    let right: Float
    let invalidRatio: Float
    let stability: Float
    let fps: Double
}

class RemoteLogger {
    static let shared = RemoteLogger()
    
    private var serverURL: URL?
    private let session = URLSession(configuration: .ephemeral)
    private var isSending = false
    
    private init() {}
    
    func configure(url: String) {
        var finalURLString = url
        // 自动修正 HTTPS 为 HTTP，因为调试服务器是纯 HTTP 的
        if finalURLString.lowercased().hasPrefix("https://") {
            print("⚠️ Detection of HTTPS in remote log URL. Switching to HTTP for local debug server.")
            finalURLString = "http://" + finalURLString.dropFirst(8)
        }
        self.serverURL = URL(string: finalURLString)
    }
    
    func log(payload: RemoteLogPayload) {
        guard let url = serverURL, !isSending else { return }
        
        isSending = true
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 2.0 // 给个较短的超时，避免阻塞
        
        do {
            let data = try JSONEncoder().encode(payload)
            request.httpBody = data
            
            let task = session.dataTask(with: request) { [weak self] _, _, _ in
                self?.isSending = false
            }
            task.resume()
        } catch {
            isSending = false
            print("❌ Failed to encode remote log: \(error)")
        }
    }
}
