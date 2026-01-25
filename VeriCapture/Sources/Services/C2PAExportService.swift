//
//  C2PAExportService.swift
//  VeriCapture
//
//  C2PA Export Service - v42.1
//  CPP証跡をC2PA互換マニフェストに変換してエクスポート
//  © 2026 VeritasChain Standards Organization
//
//  Reference: C2PA Specification v2.3
//  https://c2pa.org/specifications/
//

import Foundation
import UIKit
import CryptoKit

// MARK: - C2PA Manifest Models

/// C2PA Manifest (Simplified for export)
struct C2PAManifest: Codable {
    let manifestVersion: String
    let claim: C2PAClaim
    let signatureInfo: C2PASignatureInfo
    let assertions: [C2PAAssertion]
    
    enum CodingKeys: String, CodingKey {
        case manifestVersion = "manifest_version"
        case claim
        case signatureInfo = "signature_info"
        case assertions
    }
}

/// C2PA Claim
struct C2PAClaim: Codable {
    let claimGenerator: String
    let claimGeneratorInfo: C2PAGeneratorInfo
    let dcTitle: String
    let dcFormat: String
    let instanceId: String
    let thumbnailRef: String?
    let signature: String
    
    enum CodingKeys: String, CodingKey {
        case claimGenerator = "claim_generator"
        case claimGeneratorInfo = "claim_generator_info"
        case dcTitle = "dc:title"
        case dcFormat = "dc:format"
        case instanceId = "instanceID"
        case thumbnailRef = "thumbnail_ref"
        case signature
    }
}

/// C2PA Generator Info
struct C2PAGeneratorInfo: Codable {
    let name: String
    let version: String
    let cppVersion: String?
    let vapProfile: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case version
        case cppVersion = "vso.cpp.version"
        case vapProfile = "vso.vap.profile"
    }
}

/// C2PA Signature Info
struct C2PASignatureInfo: Codable {
    let algorithm: String
    let issuer: String?
    let time: String
    let timeSource: String?
    
    enum CodingKeys: String, CodingKey {
        case algorithm = "alg"
        case issuer
        case time
        case timeSource = "time_source"
    }
}

/// C2PA Assertion
struct C2PAAssertion: Codable {
    let label: String
    let data: C2PAAssertionData
}

/// C2PA Assertion Data (flexible)
struct C2PAAssertionData: Codable {
    // c2pa.actions
    let actions: [C2PAAction]?
    
    // c2pa.hash.data (Hard Binding)
    let exclusions: [C2PAExclusion]?
    let name: String?
    let hashAlgorithm: String?
    let hashValue: String?
    
    // stds.exif
    let exifData: [String: String]?
    
    // vso.cpp.verification
    let verificationUrl: String?
    let eventId: String?
    let eventHash: String?
    let proofType: String?
    let tsaTimestamp: String?
    let tsaService: String?
    
    enum CodingKeys: String, CodingKey {
        case actions
        case exclusions
        case name
        case hashAlgorithm = "alg"
        case hashValue = "hash"
        case exifData = "exif"
        case verificationUrl = "vso.cpp.verification_url"
        case eventId = "vso.cpp.event_id"
        case eventHash = "vso.cpp.event_hash"
        case proofType = "vso.cpp.proof_type"
        case tsaTimestamp = "vso.cpp.tsa_timestamp"
        case tsaService = "vso.cpp.tsa_service"
    }
}

/// C2PA Action
struct C2PAAction: Codable {
    let action: String
    let when: String?
    let softwareAgent: String?
    let parameters: C2PAActionParameters?
    
    enum CodingKeys: String, CodingKey {
        case action
        case when
        case softwareAgent = "softwareAgent"
        case parameters
    }
}

/// C2PA Action Parameters
struct C2PAActionParameters: Codable {
    let description: String?
    let cppEventId: String?
    let cppProofUrl: String?
    let humanAttested: Bool?
    let deviceAttested: Bool?
    
    enum CodingKeys: String, CodingKey {
        case description
        case cppEventId = "vso.cpp.event_id"
        case cppProofUrl = "vso.cpp.verification_url"
        case humanAttested = "vso.cpp.human_attested"
        case deviceAttested = "vso.cpp.device_attested"
    }
}

/// C2PA Exclusion (for hash binding)
struct C2PAExclusion: Codable {
    let start: Int
    let length: Int
}

// MARK: - C2PA Export Service

final class C2PAExportService {
    
    static let shared = C2PAExportService()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// CPP EventからC2PAマニフェストを生成
    func generateManifest(from event: CPPEvent, anchor: AnchorRecord?) -> C2PAManifest {
        let verificationUrl = "https://verify.veritaschain.org/cpp/\(event.eventId)"
        
        // Generator Info
        let generatorInfo = C2PAGeneratorInfo(
            name: "VeriCapture",
            version: DeviceInfo.appVersion,
            cppVersion: "1.1",
            vapProfile: "CPP"
        )
        
        // Claim
        let claim = C2PAClaim(
            claimGenerator: "VeriCapture/\(DeviceInfo.appVersion)",
            claimGeneratorInfo: generatorInfo,
            dcTitle: event.asset.assetName,
            dcFormat: event.asset.mimeType,
            instanceId: "xmp:iid:\(event.eventId)",
            thumbnailRef: nil,
            signature: event.signature
        )
        
        // Signature Info
        let signatureInfo = C2PASignatureInfo(
            algorithm: "ES256",
            issuer: "VeriCapture Device Key",
            time: anchor?.timestamp ?? event.timestamp,
            timeSource: anchor != nil ? "rfc3161" : "device"
        )
        
        // Assertions
        var assertions: [C2PAAssertion] = []
        
        // 1. c2pa.actions - Capture action
        let captureAction = C2PAAction(
            action: "c2pa.captured",
            when: event.timestamp,
            softwareAgent: "VeriCapture/\(DeviceInfo.appVersion)",
            parameters: C2PAActionParameters(
                description: "Cryptographic capture with CPP provenance",
                cppEventId: event.eventId,
                cppProofUrl: verificationUrl,
                humanAttested: event.captureContext.humanAttestation != nil,
                deviceAttested: true  // Always true - device key is always present
            )
        )
        
        assertions.append(C2PAAssertion(
            label: "c2pa.actions",
            data: C2PAAssertionData(
                actions: [captureAction],
                exclusions: nil,
                name: nil,
                hashAlgorithm: nil,
                hashValue: nil,
                exifData: nil,
                verificationUrl: nil,
                eventId: nil,
                eventHash: nil,
                proofType: nil,
                tsaTimestamp: nil,
                tsaService: nil
            )
        ))
        
        // 2. c2pa.hash.data - Hard binding
        assertions.append(C2PAAssertion(
            label: "c2pa.hash.data",
            data: C2PAAssertionData(
                actions: nil,
                exclusions: [],
                name: "jumbf manifest",
                hashAlgorithm: "sha256",
                hashValue: event.asset.assetHash,
                exifData: nil,
                verificationUrl: nil,
                eventId: nil,
                eventHash: nil,
                proofType: nil,
                tsaTimestamp: nil,
                tsaService: nil
            )
        ))
        
        // 3. vso.cpp.verification - CPP-specific assertion
        assertions.append(C2PAAssertion(
            label: "vso.cpp.verification",
            data: C2PAAssertionData(
                actions: nil,
                exclusions: nil,
                name: nil,
                hashAlgorithm: nil,
                hashValue: nil,
                exifData: nil,
                verificationUrl: verificationUrl,
                eventId: event.eventId,
                eventHash: event.eventHash,
                proofType: "CPP_INGEST",
                tsaTimestamp: anchor?.timestamp,
                tsaService: anchor?.serviceEndpoint
            )
        ))
        
        // 4. stds.exif - Camera settings (if available)
        if let cameraSettings = event.cameraSettings {
            var exifData: [String: String] = [:]
            
            if let iso = cameraSettings.iso {
                exifData["ISOSpeedRatings"] = String(format: "%.0f", iso)
            }
            if let exposure = cameraSettings.exposureTime {
                exifData["ExposureTime"] = formatExposureTime(exposure)
            }
            if let aperture = cameraSettings.aperture {
                exifData["FNumber"] = String(format: "%.1f", aperture)
            }
            if let focalLength = cameraSettings.focalLength {
                exifData["FocalLength"] = String(format: "%.1f", focalLength)
            }
            
            if !exifData.isEmpty {
                assertions.append(C2PAAssertion(
                    label: "stds.exif",
                    data: C2PAAssertionData(
                        actions: nil,
                        exclusions: nil,
                        name: nil,
                        hashAlgorithm: nil,
                        hashValue: nil,
                        exifData: exifData,
                        verificationUrl: nil,
                        eventId: nil,
                        eventHash: nil,
                        proofType: nil,
                        tsaTimestamp: nil,
                        tsaService: nil
                    )
                ))
            }
        }
        
        return C2PAManifest(
            manifestVersion: "2.3",
            claim: claim,
            signatureInfo: signatureInfo,
            assertions: assertions
        )
    }
    
    /// C2PAマニフェストをJSONファイルとしてエクスポート
    func exportManifestJSON(from event: CPPEvent, anchor: AnchorRecord?) throws -> URL {
        let manifest = generateManifest(from: event, anchor: anchor)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        
        let filename = "\(event.eventId).c2pa.json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url)
        
        return url
    }
    
    /// C2PA互換パッケージをZIPとしてエクスポート
    /// メディアファイル + マニフェストJSON + CPP Proof
    func exportC2PAPackage(eventId: String, includeMedia: Bool = true) async throws -> URL {
        guard let event = try StorageService.shared.getEvent(eventId: eventId) else {
            throw C2PAExportError.eventNotFound
        }
        
        let anchor = try StorageService.shared.getAnchor(forEventId: eventId)
        
        // 一時ディレクトリを作成
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folderName = "VeriCapture_C2PA_\(timestamp)"
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(folderName)
        try? FileManager.default.removeItem(at: tempDir)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // 1. C2PAマニフェストを保存
        let manifest = generateManifest(from: event, anchor: anchor)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        let manifestFilename = "\(event.asset.assetName.replacingOccurrences(of: ".", with: "_")).c2pa.json"
        let manifestURL = tempDir.appendingPathComponent(manifestFilename)
        try manifestData.write(to: manifestURL)
        
        // 2. メディアファイルを保存（オプション）
        if includeMedia {
            if let mediaData = StorageService.shared.loadMediaData(eventId: eventId) {
                let mediaURL = tempDir.appendingPathComponent(event.asset.assetName)
                try mediaData.write(to: mediaURL)
            }
        }
        
        // 3. CPP Proofを保存（フル検証用）
        let eventBuilder = CPPEventBuilder()
        let proof = eventBuilder.generateProofJSON(event: event, anchor: anchor)
        let proofData = try encoder.encode(proof)
        let proofURL = tempDir.appendingPathComponent("cpp_proof.json")
        try proofData.write(to: proofURL)
        
        // 4. READMEを追加
        let readme = generateReadme(event: event, anchor: anchor)
        let readmeURL = tempDir.appendingPathComponent("README.txt")
        try readme.write(to: readmeURL, atomically: true, encoding: .utf8)
        
        // 5. ZIPに圧縮
        let zipFilename = "\(folderName).zip"
        let zipPath = FileManager.default.temporaryDirectory.appendingPathComponent(zipFilename)
        try? FileManager.default.removeItem(at: zipPath)
        
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: tempDir, options: .forUploading, error: &error) { zipURL in
            try? FileManager.default.copyItem(at: zipURL, to: zipPath)
        }
        
        if let error = error {
            throw error
        }
        
        // 一時フォルダを削除
        try? FileManager.default.removeItem(at: tempDir)
        
        print("[C2PAExport] Package created: \(zipFilename)")
        return zipPath
    }
    
    // MARK: - Private Methods
    
    private func formatExposureTime(_ time: Double) -> String {
        if time >= 1.0 {
            return String(format: "%.1f", time)
        } else {
            let denominator = Int(1.0 / time)
            return "1/\(denominator)"
        }
    }
    
    private func generateReadme(event: CPPEvent, anchor: AnchorRecord?) -> String {
        let verificationUrl = "https://verify.veritaschain.org/cpp/\(event.eventId)"
        
        return """
        VeriCapture C2PA Export Package
        ================================
        
        This package contains C2PA-compatible provenance data exported from VeriCapture.
        
        Files:
        - *.c2pa.json    : C2PA Manifest (JSON format)
        - cpp_proof.json : Full CPP (Capture Provenance Profile) proof
        - media file     : Original captured media (if included)
        
        Verification:
        -------------
        Online:  \(verificationUrl)
        
        Event ID:      \(event.eventId)
        Event Hash:    \(event.eventHash)
        Asset Hash:    \(event.asset.assetHash)
        Captured:      \(event.timestamp)
        TSA Anchored:  \(anchor?.timestamp ?? "Not anchored")
        TSA Service:   \(anchor?.serviceEndpoint ?? "N/A")
        
        C2PA Compatibility:
        -------------------
        This package follows C2PA Specification v2.3 format.
        The c2pa.json manifest can be used with C2PA-compatible tools.
        
        CPP extensions (vso.cpp.*) provide additional verification:
        - Independent TSA timestamp (RFC 3161)
        - Cryptographic event chain
        - Human presence attestation (if enabled)
        
        For more information:
        - VeriCapture: https://veritaschain.org/vap/cpp/vericapture
        - CPP Spec:    https://github.com/veritaschain/cpp-spec
        - C2PA:        https://c2pa.org
        
        © 2026 VeritasChain Standards Organization
        """
    }
}

// MARK: - Errors

enum C2PAExportError: LocalizedError {
    case eventNotFound
    case exportFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .eventNotFound:
            return "Event not found"
        case .exportFailed(let reason):
            return "C2PA export failed: \(reason)"
        }
    }
}
