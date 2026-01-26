//
//  Utils.swift
//  VeraSnap
//
//  Utility functions: UUIDv7, JSON Canonicalization, Device Info
//  © 2026 VeritasChain Standards Organization
//

import Foundation
import UIKit
import CryptoKit

// MARK: - App Constants

enum AppConstants {
    /// App Store URL（公開後に実際のIDに差し替え）
    static let appStoreURL = "https://apps.apple.com/app/verasnap/id0000000000"
    
    /// App Store ID（公開後に実際のIDに差し替え）
    static let appStoreID = "0000000000"
    
    /// アプリ名
    static let appName = "VeraSnap"
    
    /// キャッチコピー（ローカライズ対応）
    static var tagline: String { L10n.App.tagline }
    
    /// バージョン
    static let version = "1.0.0"
}

// MARK: - UUIDv7 Generator (RFC 9562)

enum UUIDv7 {
    
    static func generate() -> String {
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        return generate(timestamp: timestamp)
    }
    
    static func generate(timestamp: UInt64) -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        
        bytes[0] = UInt8((timestamp >> 40) & 0xFF)
        bytes[1] = UInt8((timestamp >> 32) & 0xFF)
        bytes[2] = UInt8((timestamp >> 24) & 0xFF)
        bytes[3] = UInt8((timestamp >> 16) & 0xFF)
        bytes[4] = UInt8((timestamp >> 8) & 0xFF)
        bytes[5] = UInt8(timestamp & 0xFF)
        
        var randomBytes = [UInt8](repeating: 0, count: 10)
        _ = SecRandomCopyBytes(kSecRandomDefault, 10, &randomBytes)
        
        bytes[6] = (0x70 | (randomBytes[0] & 0x0F))
        bytes[7] = randomBytes[1]
        bytes[8] = (0x80 | (randomBytes[2] & 0x3F))
        bytes[9] = randomBytes[3]
        bytes[10] = randomBytes[4]
        bytes[11] = randomBytes[5]
        bytes[12] = randomBytes[6]
        bytes[13] = randomBytes[7]
        bytes[14] = randomBytes[8]
        bytes[15] = randomBytes[9]
        
        return formatUUID(bytes: bytes)
    }
    
    private static func formatUUID(bytes: [UInt8]) -> String {
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let idx = hex.index(hex.startIndex, offsetBy: 8)
        let idx2 = hex.index(idx, offsetBy: 4)
        let idx3 = hex.index(idx2, offsetBy: 4)
        let idx4 = hex.index(idx3, offsetBy: 4)
        return "\(hex[..<idx])-\(hex[idx..<idx2])-\(hex[idx2..<idx3])-\(hex[idx3..<idx4])-\(hex[idx4...])"
    }
}

// MARK: - ISO 8601 Date Extensions

extension Date {
    var iso8601String: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
    
    static func fromISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}

// MARK: - JSON Canonicalizer (RFC 8785 JCS)

enum JSONCanonicalizer {
    
    enum CanonicalizationError: Error {
        case unsupportedType
        case encodingFailed
    }
    
    static func canonicalize(_ object: Any) throws -> Data {
        let canonicalString = try canonicalizeToString(object)
        guard let data = canonicalString.data(using: .utf8) else {
            throw CanonicalizationError.encodingFailed
        }
        return data
    }
    
    static func canonicalizeToString(_ object: Any) throws -> String {
        switch object {
        case is NSNull:
            return "null"
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            return canonicalizeNumber(number)
        case let string as String:
            return canonicalizeString(string)
        case let array as [Any]:
            let elements = try array.map { try canonicalizeToString($0) }
            return "[\(elements.joined(separator: ","))]"
        case let dict as [String: Any]:
            let sortedKeys = dict.keys.sorted { $0.compare($1, options: .literal) == .orderedAscending }
            let pairs = try sortedKeys.map { key -> String in
                let value = try canonicalizeToString(dict[key]!)
                return "\(canonicalizeString(key)):\(value)"
            }
            return "{\(pairs.joined(separator: ","))}"
        default:
            throw CanonicalizationError.unsupportedType
        }
    }
    
    private static func canonicalizeNumber(_ number: NSNumber) -> String {
        let objCType = String(cString: number.objCType)
        if objCType == "c" || objCType == "B" {
            return number.boolValue ? "true" : "false"
        }
        if number.doubleValue == Double(number.int64Value) {
            return "\(number.int64Value)"
        }
        let double = number.doubleValue
        if double.isNaN || double.isInfinite {
            return "null"
        }
        return "\(double)"
    }
    
    private static func canonicalizeString(_ string: String) -> String {
        var result = "\""
        for char in string {
            switch char {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                let scalar = char.unicodeScalars.first!.value
                if scalar < 0x20 {
                    result += String(format: "\\u%04x", scalar)
                } else {
                    result += String(char)
                }
            }
        }
        result += "\""
        return result
    }
}

// MARK: - Device Info

@MainActor
enum DeviceInfo {
    
    static var deviceId: String {
        guard let identifierForVendor = UIDevice.current.identifierForVendor else {
            return "unknown"
        }
        return "sha256:\(identifierForVendor.uuidString.sha256Hash)"
    }
    
    static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        return mapToDeviceName(modelCode ?? "Unknown")
    }
    
    static var osVersion: String {
        "iOS \(UIDevice.current.systemVersion)"
    }
    
    static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "VeraSnap/\(version)"
    }
    
    private static func mapToDeviceName(_ code: String) -> String {
        let deviceMap: [String: String] = [
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "x86_64": "Simulator",
            "arm64": "Simulator (Apple Silicon)"
        ]
        return deviceMap[code] ?? code
    }
}

// MARK: - String Extensions

extension String {
    var sha256Hash: String {
        guard let data = self.data(using: .utf8) else { return "" }
        return data.sha256Hash
    }
}

// MARK: - Data Extensions

extension Data {
    var sha256Hash: String {
        let hash = SHA256.hash(data: self)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    var sha256Prefixed: String {
        "sha256:\(sha256Hash)"
    }
    
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
    
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}

// MARK: - SHA256Digest Extension

extension SHA256Digest {
    /// SHA256Digestをhex文字列に変換
    var hexString: String {
        self.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Streaming Hash for Large Files (Video)

enum StreamingHash {
    
    /// ファイルをストリーミングでハッシュ計算（大容量動画対応）
    /// - Parameters:
    ///   - url: ファイルのURL
    ///   - bufferSize: バッファサイズ（デフォルト: 64KB）
    /// - Returns: SHA-256ハッシュ（sha256:prefixed）
    static func sha256(fileAt url: URL, bufferSize: Int = 64 * 1024) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        
        var hasher = SHA256()
        
        while autoreleasepool(invoking: {
            let data = fileHandle.readData(ofLength: bufferSize)
            if data.isEmpty { return false }
            hasher.update(data: data)
            return true
        }) {}
        
        let digest = hasher.finalize()
        let hashString = digest.compactMap { String(format: "%02x", $0) }.joined()
        return "sha256:\(hashString)"
    }
    
    /// 進捗コールバック付きストリーミングハッシュ
    /// - Parameters:
    ///   - url: ファイルのURL
    ///   - progressHandler: 進捗ハンドラ（0.0-1.0）
    /// - Returns: SHA-256ハッシュ（sha256:prefixed）
    static func sha256(fileAt url: URL, progressHandler: @escaping (Double) -> Void) throws -> String {
        let bufferSize = 64 * 1024  // 64KB
        
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        
        var hasher = SHA256()
        var processedBytes: Int64 = 0
        
        while autoreleasepool(invoking: {
            let data = fileHandle.readData(ofLength: bufferSize)
            if data.isEmpty { return false }
            hasher.update(data: data)
            processedBytes += Int64(data.count)
            
            if fileSize > 0 {
                let progress = Double(processedBytes) / Double(fileSize)
                progressHandler(min(progress, 1.0))
            }
            return true
        }) {}
        
        let digest = hasher.finalize()
        let hashString = digest.compactMap { String(format: "%02x", $0) }.joined()
        return "sha256:\(hashString)"
    }
}

// MARK: - Reference Watermark for Shared Images

enum ReferenceWatermark {
    
    /// 参照用プレビューの斜め透かしを追加
    /// - Parameter image: 元の画像
    /// - Returns: 透かし付きの画像
    static func addWatermark(to image: UIImage) -> UIImage {
        let watermarkText = "REFERENCE PREVIEW"
        
        let size = image.size
        let scale = image.scale
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        
        // 元の画像を描画
        image.draw(at: .zero)
        
        guard let context = UIGraphicsGetCurrentContext() else {
            return image
        }
        
        // 透かしの設定
        let fontSize: CGFloat = min(size.width, size.height) / 10
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white.withAlphaComponent(0.5),
            .paragraphStyle: paragraphStyle
        ]
        
        // テキストサイズを計算
        let textSize = watermarkText.size(withAttributes: attributes)
        
        // 斜め配置のための回転と繰り返し
        context.saveGState()
        
        // 中心を基準に-30度回転
        context.translateBy(x: size.width / 2, y: size.height / 2)
        context.rotate(by: -.pi / 6) // -30度
        
        // 繰り返し配置のための計算
        let diagonal = sqrt(size.width * size.width + size.height * size.height)
        let spacing = textSize.height * 2.5
        let rows = Int(diagonal / spacing) + 2
        let cols = Int(diagonal / (textSize.width * 1.2)) + 2
        
        // 透かしを繰り返し描画
        for row in -rows...rows {
            for col in -cols...cols {
                let x = CGFloat(col) * textSize.width * 1.2
                let y = CGFloat(row) * spacing
                
                // 影（アウトライン効果）
                let shadowAttributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.black.withAlphaComponent(0.3),
                    .paragraphStyle: paragraphStyle
                ]
                watermarkText.draw(
                    in: CGRect(x: x - textSize.width / 2 + 2, y: y - textSize.height / 2 + 2, width: textSize.width, height: textSize.height),
                    withAttributes: shadowAttributes
                )
                
                // 本体
                watermarkText.draw(
                    in: CGRect(x: x - textSize.width / 2, y: y - textSize.height / 2, width: textSize.width, height: textSize.height),
                    withAttributes: attributes
                )
            }
        }
        
        context.restoreGState()
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
}
