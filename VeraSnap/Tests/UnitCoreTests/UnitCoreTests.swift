import XCTest
import Security
@testable import VeriCaptureCore

final class UnitCoreTests: XCTestCase {
    // Tests/Fixtures 配下のフィクスチャフォルダ名。
    private enum FixtureNames {
        static let ok = "ok_01"
        static let tamperAsset = "tamper_asset_bitflip_01"
        static let tamperProof = "tamper_proof_field_01"
    }

    // SHA-256 の既知ベクタが安定しているか確認（空文字と "abc"）。
    func testSHA256KnownVectors() {
        XCTAssertEqual(
            CryptoVerificationService.sha256(Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(
            CryptoVerificationService.sha256("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    // 正常フィクスチャで assetHash が proof と一致することを確認。
    func testAssetHashMatchesProof() throws {
        let assetData = try FixtureLoader.data(
            fixture: FixtureNames.ok,
            fileName: "ok_01_asset.bin"
        )
        let proof = try FixtureLoader.proof(
            fixture: FixtureNames.ok,
            fileName: "ok_01_proof.json"
        )

        XCTAssertTrue(
            CryptoVerificationService.verifyAssetHash(
                assetData: assetData,
                expectedHash: proof.event.asset.assetHash
            )
        )
    }

    // 1バイト改変で assetHash が不一致になることを確認。
    func testAssetHashMismatchForTamperedAsset() throws {
        let assetData = try FixtureLoader.data(
            fixture: FixtureNames.tamperAsset,
            fileName: "tamper_asset_bitflip_01_asset_tampered.bin"
        )
        let proof = try FixtureLoader.proof(
            fixture: FixtureNames.tamperAsset,
            fileName: "tamper_asset_bitflip_01_proof.json"
        )

        XCTAssertFalse(
            CryptoVerificationService.verifyAssetHash(
                assetData: assetData,
                expectedHash: proof.event.asset.assetHash
            )
        )
    }

    // JCS正規化で再計算した eventHash が proof と一致することを確認。
    func testEventHashMatchesProof() throws {
        let proof = try FixtureLoader.proof(
            fixture: FixtureNames.ok,
            fileName: "ok_01_proof.json"
        )

        XCTAssertTrue(try CryptoVerificationService.verifyEventHash(event: proof.event))
    }

    // proof の一部改変で eventHash 検証が失敗することを確認。
    func testEventHashFailsForTamperedProof() throws {
        let proof = try FixtureLoader.proof(
            fixture: FixtureNames.tamperProof,
            fileName: "tamper_proof_field_01_proof_tampered.json"
        )

        XCTAssertFalse(try CryptoVerificationService.verifyEventHash(event: proof.event))
    }

    // 正常署名は通り、payload改変や公開鍵差し替えは失敗することを確認。
    func testSignaturePassesAndFailsWithPayloadOrKeyChange() throws {
        let (privateKey, publicKey) = try SecKeyFactory.generateKeyPair()
        let payload = Data("payload".utf8)
        let payloadHash = CryptoVerificationService.sha256(payload)
        let publicKeyBase64 = try SecKeyFactory.publicKeyBase64(publicKey: publicKey)

        var event = CPPEventJSON(
            eventID: "evt-test",
            chainID: "chain-test",
            prevHash: "GENESIS",
            timestamp: "2026-01-21T00:00:00Z",
            eventType: "CAPTURE",
            hashAlgo: "SHA-256",
            signAlgo: "ES256",
            asset: AssetInfoJSON(
                assetID: "asset-test",
                assetType: "image",
                assetHash: "sha256:\(payloadHash)",
                assetName: "payload.bin",
                assetSize: payload.count,
                mimeType: "application/octet-stream",
                videoMetadata: nil
            ),
            captureContext: CaptureContextJSON(
                deviceID: "device-test",
                deviceModel: "iPhone15,3",
                osVersion: "iOS 17.0",
                appVersion: "0.1.0",
                keyAttestation: nil,
                humanAttestation: nil
            ),
            sensorData: nil,
            cameraSettings: nil,
            signerInfo: nil,
            eventHash: "",
            signature: ""
        )

        let eventHash = try CryptoVerificationService.computeEventHash(event: event)
        let messageHash = Data(verifyHexString: eventHash.replacingOccurrences(of: "sha256:", with: ""))
        XCTAssertNotNil(messageHash)

        let signature = try SecKeyFactory.sign(
            messageHash: messageHash ?? Data(),
            privateKey: privateKey
        )

        event = CPPEventJSON(
            eventID: event.eventID,
            chainID: event.chainID,
            prevHash: event.prevHash,
            timestamp: event.timestamp,
            eventType: event.eventType,
            hashAlgo: event.hashAlgo,
            signAlgo: event.signAlgo,
            asset: event.asset,
            captureContext: event.captureContext,
            sensorData: event.sensorData,
            cameraSettings: event.cameraSettings,
            signerInfo: event.signerInfo,
            eventHash: eventHash,
            signature: "es256:\(signature.base64EncodedString())"
        )

        XCTAssertTrue(
            try CryptoVerificationService.verifySignature(
                event: event,
                publicKeyBase64: publicKeyBase64
            )
        )

        let tamperedAsset = AssetInfoJSON(
            assetID: event.asset.assetID,
            assetType: event.asset.assetType,
            assetHash: event.asset.assetHash,
            assetName: "payload-tampered.bin",
            assetSize: event.asset.assetSize,
            mimeType: event.asset.mimeType,
            videoMetadata: event.asset.videoMetadata
        )

        let tamperedEvent = CPPEventJSON(
            eventID: event.eventID,
            chainID: event.chainID,
            prevHash: event.prevHash,
            timestamp: event.timestamp,
            eventType: event.eventType,
            hashAlgo: event.hashAlgo,
            signAlgo: event.signAlgo,
            asset: tamperedAsset,
            captureContext: event.captureContext,
            sensorData: event.sensorData,
            cameraSettings: event.cameraSettings,
            signerInfo: nil,
            eventHash: event.eventHash,
            signature: event.signature
        )

        XCTAssertFalse(
            try CryptoVerificationService.verifySignature(
                event: tamperedEvent,
                publicKeyBase64: publicKeyBase64
            )
        )

        let (_, otherPublicKey) = try SecKeyFactory.generateKeyPair()
        let otherPublicKeyBase64 = try SecKeyFactory.publicKeyBase64(publicKey: otherPublicKey)

        XCTAssertFalse(
            try CryptoVerificationService.verifySignature(
                event: event,
                publicKeyBase64: otherPublicKeyBase64
            )
        )
    }
}

private enum FixtureLoader {
    // リポジトリ内の実ファイルからフィクスチャを取得（CIでも同じパスで参照可能）。
    private static func fixtureURL(fixture: String, fileName: String) throws -> URL {
        let testsDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = testsDir.appendingPathComponent("Fixtures")
            .appendingPathComponent(fixture)
            .appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(
                domain: "UnitCoreTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing fixture: Fixtures/\(fixture)/\(fileName)"]
            )
        }
        return url
    }

    static func data(fixture: String, fileName: String) throws -> Data {
        return try Data(contentsOf: fixtureURL(fixture: fixture, fileName: fileName))
    }

    static func proof(fixture: String, fileName: String) throws -> CPPProofJSON {
        let data = try self.data(fixture: fixture, fileName: fileName)
        return try JSONDecoder().decode(CPPProofJSON.self, from: data)
    }
}

private enum SecKeyFactory {
    // 署名検証用の一時P-256鍵を生成。
    static func generateKeyPair() throws -> (SecKey, SecKey) {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrIsPermanent as String: false
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw NSError(domain: "UnitCoreTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "Public key missing"])
        }

        return (privateKey, publicKey)
    }

    static func sign(messageHash: Data, privateKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureDigestX962SHA256,
            messageHash as CFData,
            &error
        ) as Data? else {
            throw error!.takeRetainedValue() as Error
        }
        return signature
    }

    // 署名検証入力に合わせて公開鍵をBase64で出力。
    static func publicKeyBase64(publicKey: SecKey) throws -> String {
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw error!.takeRetainedValue() as Error
        }
        return data.base64EncodedString()
    }
}
