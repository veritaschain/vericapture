//
//  BiometricAuthService.swift
//  VeriCapture
//
//  Biometric Authentication Service (Face ID / Touch ID)
//  © 2026 VeritasChain Standards Organization
//
//  Phase A Design: 認証失敗時も撮影を許可し、verified=falseとして記録

import LocalAuthentication
import Foundation

/// 生体認証サービス
/// Thread Safety: Sendable準拠、すべてのメソッドはスレッドセーフ
final class BiometricAuthService: Sendable {
    
    static let shared = BiometricAuthService()
    
    private init() {}
    
    // MARK: - Public Types
    
    enum AuthResult: Sendable {
        case success
        case failed(String)
        case cancelled
        case notAvailable
    }
    
    struct VerifiedCaptureAuthResult: Sendable {
        let attempted: Bool
        let success: Bool
        let method: String
        let attemptedAt: Date
        let sessionNonce: String
        let failureReason: String?
        
        // nonisolatedを明示してSwift 6対応
        nonisolated static func succeeded(method: String, at: Date, nonce: String) -> Self {
            .init(attempted: true, success: true, method: method, attemptedAt: at, sessionNonce: nonce, failureReason: nil)
        }
        
        nonisolated static func failed(method: String, at: Date, nonce: String, reason: String) -> Self {
            .init(attempted: true, success: false, method: method, attemptedAt: at, sessionNonce: nonce, failureReason: reason)
        }
        
        nonisolated static func cancelled(method: String, at: Date, nonce: String) -> Self {
            .init(attempted: true, success: false, method: method, attemptedAt: at, sessionNonce: nonce, failureReason: "UserCancelled")
        }
        
        nonisolated static func notAvailable() -> Self {
            .init(attempted: false, success: false, method: "None", attemptedAt: Date(), sessionNonce: "", failureReason: "BiometryNotAvailable")
        }
    }
    
    enum AuthPurpose: Sendable {
        case deleteProof
        case exportFullProof
        case verifiedCapture
        case resetChain
        
        var localizedReason: String {
            switch self {
            case .deleteProof:
                return "biometric.delete_proof".localized
            case .exportFullProof:
                return "biometric.export_full_proof".localized
            case .verifiedCapture:
                return "biometric.verified_capture".localized
            case .resetChain:
                return "biometric.reset_chain".localized
            }
        }
    }
    
    // MARK: - Properties (Computed)
    
    /// 生体認証が利用可能かチェック
    nonisolated var isDeviceAuthAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }
    
    /// 生体認証の種類名を取得
    nonisolated var biometryTypeName: String {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .none: return "パスコード"
        @unknown default: return "認証"
        }
    }
    
    // MARK: - Async Authentication Methods
    
    /// 認証を実行
    nonisolated func authenticate(for purpose: AuthPurpose) async -> AuthResult {
        let context = LAContext()
        context.localizedCancelTitle = "キャンセル"
        context.localizedFallbackTitle = "パスコードを使用"
        
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .notAvailable
        }
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: purpose.localizedReason
            )
            return success ? .success : .failed("Authentication failed")
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                return .cancelled
            default:
                return .failed(error.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
    
    // MARK: - Verified Capture Mode Authentication
    
    /// Verified Capture Mode用の認証
    nonisolated func authenticateForVerifiedCapture() async -> VerifiedCaptureAuthResult {
        let context = LAContext()
        context.localizedCancelTitle = "キャンセル"
        context.localizedFallbackTitle = "パスコードを使用"
        
        let attemptedAt = Date()
        let sessionNonce = generateSessionNonce()
        
        var error: NSError?
        
        // 1. 利用可能チェック
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .notAvailable()
        }
        
        let method = biometryTypeString(context.biometryType)
        
        // 2. 認証実行
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: AuthPurpose.verifiedCapture.localizedReason
            )
            
            if success {
                return .succeeded(method: method, at: attemptedAt, nonce: sessionNonce)
            } else {
                return .failed(method: method, at: attemptedAt, nonce: sessionNonce, reason: "Authentication Failed")
            }
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .appCancel, .systemCancel:
                return .cancelled(method: method, at: attemptedAt, nonce: sessionNonce)
            default:
                return .failed(method: method, at: attemptedAt, nonce: sessionNonce, reason: laError.localizedDescription)
            }
        } catch {
            return .failed(method: method, at: attemptedAt, nonce: sessionNonce, reason: error.localizedDescription)
        }
    }
    
    // MARK: - Helpers (nonisolated for Swift 6)
    
    nonisolated private func biometryTypeString(_ type: LABiometryType) -> String {
        switch type {
        case .faceID: return "FaceID"
        case .touchID: return "TouchID"
        case .opticID: return "OpticID"
        case .none: return "Passcode"
        @unknown default: return "Unknown"
        }
    }
    
    nonisolated private func generateSessionNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }
}
