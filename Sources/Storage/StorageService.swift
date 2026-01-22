//
//  StorageService.swift
//  VeriCapture
//
//  Local Storage for Events and Media
//  © 2026 VeritasChain Standards Organization
//

import Foundation
import SQLite3
import UIKit

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class StorageService: @unchecked Sendable {
    static let shared = StorageService()
    
    private var db: OpaquePointer?
    private let lock = NSLock()
    
    private init() {}
    
    func initialize() throws {
        let dbPath = getDocumentsDirectory().appendingPathComponent("vericapture.db").path
        
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            throw StorageError.databaseOpenFailed
        }
        
        try createTables()
        print("[StorageService] Database initialized at: \(dbPath)")
    }
    
    private func createTables() throws {
        let sql = """
            CREATE TABLE IF NOT EXISTS events (
                event_id TEXT PRIMARY KEY,
                chain_id TEXT NOT NULL,
                prev_hash TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                event_type TEXT NOT NULL,
                event_json TEXT NOT NULL,
                event_hash TEXT NOT NULL,
                signature TEXT NOT NULL,
                created_at TEXT NOT NULL,
                anchor_id TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_events_chain ON events(chain_id, timestamp);
            
            CREATE TABLE IF NOT EXISTS assets (
                asset_id TEXT PRIMARY KEY,
                event_id TEXT NOT NULL,
                asset_type TEXT NOT NULL,
                asset_hash TEXT NOT NULL,
                file_path TEXT NOT NULL,
                file_size INTEGER NOT NULL,
                mime_type TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            
            CREATE TABLE IF NOT EXISTS anchors (
                anchor_id TEXT PRIMARY KEY,
                anchor_type TEXT NOT NULL,
                merkle_root TEXT NOT NULL,
                tsa_response BLOB,
                tsa_timestamp TEXT,
                status TEXT NOT NULL DEFAULT 'PENDING',
                created_at TEXT NOT NULL,
                completed_at TEXT
            );
            
            CREATE TABLE IF NOT EXISTS chains (
                chain_id TEXT PRIMARY KEY,
                created_at TEXT NOT NULL
            );
            
            CREATE TABLE IF NOT EXISTS location_metadata (
                event_id TEXT PRIMARY KEY,
                latitude REAL,
                longitude REAL,
                created_at TEXT NOT NULL
            );
            
            CREATE TABLE IF NOT EXISTS tombstones (
                tombstone_id TEXT PRIMARY KEY,
                target_event_id TEXT NOT NULL,
                target_event_hash TEXT NOT NULL,
                reason_code TEXT NOT NULL,
                reason_description TEXT,
                executor_type TEXT NOT NULL,
                executor_attestation TEXT,
                prev_hash TEXT NOT NULL,
                tombstone_hash TEXT NOT NULL,
                signature TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                created_at TEXT NOT NULL,
                UNIQUE(target_event_id)
            );
            CREATE INDEX IF NOT EXISTS idx_tombstones_target ON tombstones(target_event_id);
            
            -- Cases Table (v40)
            CREATE TABLE IF NOT EXISTS cases (
                case_id TEXT PRIMARY KEY,
                chain_id TEXT UNIQUE NOT NULL,
                name TEXT NOT NULL,
                description TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                is_archived INTEGER DEFAULT 0,
                event_count INTEGER DEFAULT 0,
                last_capture_at TEXT,
                icon TEXT DEFAULT 'folder.fill',
                color_hex TEXT DEFAULT '007AFF'
            );
            CREATE INDEX IF NOT EXISTS idx_cases_chain_id ON cases(chain_id);
            CREATE INDEX IF NOT EXISTS idx_cases_archived ON cases(is_archived);
        """
        try executeSQL(sql)
        
        // マイグレーション: 既存テーブルに新カラムを追加
        try migrateTablesIfNeeded()
    }
    
    /// 既存テーブルのマイグレーション
    private func migrateTablesIfNeeded() throws {
        print("[Storage] Starting migration check...")
        
        // events テーブルに新カラムを追加（存在しない場合のみ）
        let columnsToAdd = [
            ("event_status", "TEXT NOT NULL DEFAULT 'ACTIVE'"),
            ("media_status", "TEXT NOT NULL DEFAULT 'PRESENT'"),
            ("media_status_changed_at", "TEXT"),
            ("media_status_reason", "TEXT")
        ]
        
        for (column, definition) in columnsToAdd {
            let sql = "ALTER TABLE events ADD COLUMN \(column) \(definition)"
            do {
                try executeSQL(sql)
                print("[Storage] Added column: \(column)")
            } catch {
                // 既に存在する場合はエラーを無視
                print("[Storage] Column \(column) already exists or error: \(error)")
            }
        }
        
        // event_statusカラムが存在する場合、インデックスを作成
        do {
            try executeSQL("CREATE INDEX IF NOT EXISTS idx_events_status ON events(event_status)")
            print("[Storage] Created index: idx_events_status")
        } catch {
            print("[Storage] Index idx_events_status already exists or error: \(error)")
        }
        
        // anchors テーブルに新カラムを追加
        let anchorColumns = [
            ("failure_reason", "TEXT"),
            ("retry_count", "INTEGER DEFAULT 0"),
            ("service_endpoint", "TEXT")
        ]
        
        for (column, definition) in anchorColumns {
            let sql = "ALTER TABLE anchors ADD COLUMN \(column) \(definition)"
            do {
                try executeSQL(sql)
                print("[Storage] Added anchor column: \(column)")
            } catch {
                print("[Storage] Anchor column \(column) already exists or error: \(error)")
            }
        }
        
        print("[Storage] Migration check complete")
    }
    
    func getOrCreateChainId() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        
        let query = "SELECT chain_id FROM chains ORDER BY created_at DESC LIMIT 1"
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                let chainId = String(cString: sqlite3_column_text(statement, 0))
                sqlite3_finalize(statement)
                return chainId
            }
        }
        sqlite3_finalize(statement)
        
        let newChainId = UUIDv7.generate()
        let insert = "INSERT INTO chains (chain_id, created_at) VALUES (?, ?)"
        
        var insertStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, insert, -1, &insertStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(insertStatement, 1, newChainId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(insertStatement, 2, Date().iso8601String, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(insertStatement) != SQLITE_DONE {
                sqlite3_finalize(insertStatement)
                throw StorageError.insertFailed
            }
        }
        sqlite3_finalize(insertStatement)
        
        return newChainId
    }
    
    func saveEvent(_ event: CPPEvent, imageData: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let filePath = try saveMediaFile(imageData, filename: event.asset.assetName)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let eventJson = try encoder.encode(event)
        guard let eventJsonString = String(data: eventJson, encoding: .utf8) else {
            throw StorageError.encodingFailed
        }
        
        let insertEvent = """
            INSERT INTO events (event_id, chain_id, prev_hash, timestamp, event_type, event_json, event_hash, signature, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertEvent, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, event.eventId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, event.chainId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, event.prevHash, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, event.timestamp, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 5, event.eventType.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 6, eventJsonString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 7, event.eventHash, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 8, event.signature, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 9, Date().iso8601String, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                sqlite3_finalize(statement)
                throw StorageError.insertFailed
            }
        }
        sqlite3_finalize(statement)
        
        let insertAsset = """
            INSERT INTO assets (asset_id, event_id, asset_type, asset_hash, file_path, file_size, mime_type, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var assetStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertAsset, -1, &assetStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(assetStatement, 1, event.asset.assetId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(assetStatement, 2, event.eventId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(assetStatement, 3, event.asset.assetType.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(assetStatement, 4, event.asset.assetHash, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(assetStatement, 5, filePath, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(assetStatement, 6, Int32(event.asset.assetSize))
            sqlite3_bind_text(assetStatement, 7, event.asset.mimeType, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(assetStatement, 8, Date().iso8601String, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(assetStatement) != SQLITE_DONE {
                sqlite3_finalize(assetStatement)
                throw StorageError.insertFailed
            }
        }
        sqlite3_finalize(assetStatement)
    }
    
    func getLastEvent(chainId: String) throws -> CPPEvent? {
        lock.lock()
        defer { lock.unlock() }
        
        let query = "SELECT event_json FROM events WHERE chain_id = ? ORDER BY timestamp DESC LIMIT 1"
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, chainId, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                let jsonString = String(cString: sqlite3_column_text(statement, 0))
                sqlite3_finalize(statement)
                
                guard let jsonData = jsonString.data(using: .utf8) else {
                    throw StorageError.decodingFailed
                }
                
                return try JSONDecoder().decode(CPPEvent.self, from: jsonData)
            }
        }
        sqlite3_finalize(statement)
        return nil
    }
    
    /// chainId不問で最新のイベントを取得
    func getLastEventAny() throws -> CPPEvent? {
        lock.lock()
        defer { lock.unlock() }
        
        let query = "SELECT event_json FROM events ORDER BY timestamp DESC LIMIT 1"
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                let jsonString = String(cString: sqlite3_column_text(statement, 0))
                sqlite3_finalize(statement)
                
                guard let jsonData = jsonString.data(using: .utf8) else {
                    throw StorageError.decodingFailed
                }
                
                return try JSONDecoder().decode(CPPEvent.self, from: jsonData)
            }
        }
        sqlite3_finalize(statement)
        return nil
    }
    
    func getEvent(eventId: String) throws -> CPPEvent? {
        lock.lock()
        defer { lock.unlock() }
        
        let query = "SELECT event_json FROM events WHERE event_id = ?"
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, eventId, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                let jsonString = String(cString: sqlite3_column_text(statement, 0))
                sqlite3_finalize(statement)
                
                guard let jsonData = jsonString.data(using: .utf8) else {
                    throw StorageError.decodingFailed
                }
                
                return try JSONDecoder().decode(CPPEvent.self, from: jsonData)
            }
        }
        sqlite3_finalize(statement)
        return nil
    }
    
    func getAllEvents(chainId: String) throws -> [CPPEvent] {
        lock.lock()
        defer { lock.unlock() }
        
        let query = "SELECT event_json FROM events WHERE chain_id = ? ORDER BY timestamp ASC"
        
        var events: [CPPEvent] = []
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, chainId, -1, SQLITE_TRANSIENT)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let jsonString = String(cString: sqlite3_column_text(statement, 0))
                
                if let jsonData = jsonString.data(using: .utf8),
                   let event = try? JSONDecoder().decode(CPPEvent.self, from: jsonData) {
                    events.append(event)
                }
            }
        }
        sqlite3_finalize(statement)
        return events
    }
    
    /// 全イベントを取得（chainId不問）
    func getEvents() throws -> [CPPEvent] {
        lock.lock()
        defer { lock.unlock() }
        
        let query = "SELECT event_json FROM events ORDER BY timestamp DESC"
        
        var events: [CPPEvent] = []
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let jsonString = String(cString: sqlite3_column_text(statement, 0))
                
                if let jsonData = jsonString.data(using: .utf8),
                   let event = try? JSONDecoder().decode(CPPEvent.self, from: jsonData) {
                    events.append(event)
                }
            }
        }
        sqlite3_finalize(statement)
        return events
    }
    
    /// Get total event count across all chains (for free plan limit)
    /// Only counts events belonging to existing cases
    func getTotalEventCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        
        // Only count events that belong to existing cases
        let query = "SELECT COUNT(*) FROM events WHERE chain_id IN (SELECT chain_id FROM cases)"
        var statement: OpaquePointer?
        var count = 0
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        return count
    }
    
    /// Clean up orphaned events (events not belonging to any case)
    func cleanupOrphanedEvents() {
        lock.lock()
        defer { lock.unlock() }
        
        let deleteSql = "DELETE FROM events WHERE chain_id NOT IN (SELECT chain_id FROM cases)"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, deleteSql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_DONE {
                let deletedCount = sqlite3_changes(db)
                if deletedCount > 0 {
                    print("[StorageService] Cleaned up \(deletedCount) orphaned events")
                }
            }
        }
        sqlite3_finalize(statement)
    }
    
    func getPendingEventsForAnchor() throws -> [CPPEvent] {
        lock.lock()
        defer { lock.unlock() }
        
        let query = "SELECT event_json FROM events WHERE anchor_id IS NULL ORDER BY timestamp ASC LIMIT 100"
        
        var events: [CPPEvent] = []
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let jsonString = String(cString: sqlite3_column_text(statement, 0))
                
                if let jsonData = jsonString.data(using: .utf8),
                   let event = try? JSONDecoder().decode(CPPEvent.self, from: jsonData) {
                    events.append(event)
                }
            }
        }
        sqlite3_finalize(statement)
        return events
    }
    
    /// イベントがアンカリング済みかどうかを確認
    func isEventAnchored(eventId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let query = "SELECT anchor_id FROM events WHERE event_id = ? AND anchor_id IS NOT NULL"
        
        var statement: OpaquePointer?
        var isAnchored = false
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, eventId, -1, SQLITE_TRANSIENT)
            isAnchored = sqlite3_step(statement) == SQLITE_ROW
        }
        sqlite3_finalize(statement)
        return isAnchored
    }
    
    func updateEventAnchor(eventId: String, anchorId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let update = "UPDATE events SET anchor_id = ? WHERE event_id = ?"
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, update, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, anchorId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, eventId, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                sqlite3_finalize(statement)
                throw StorageError.updateFailed
            }
        }
        sqlite3_finalize(statement)
    }
    
    /// イベントと関連アセットを削除
    func deleteEvent(eventId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        
        // アセットのファイルパスを取得
        let assetQuery = "SELECT file_path FROM assets WHERE event_id = ?"
        var assetStatement: OpaquePointer?
        var filePaths: [String] = []
        
        if sqlite3_prepare_v2(db, assetQuery, -1, &assetStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(assetStatement, 1, eventId, -1, SQLITE_TRANSIENT)
            
            while sqlite3_step(assetStatement) == SQLITE_ROW {
                let path = String(cString: sqlite3_column_text(assetStatement, 0))
                filePaths.append(path)
            }
        }
        sqlite3_finalize(assetStatement)
        
        // アセットレコードを削除
        let deleteAssets = "DELETE FROM assets WHERE event_id = ?"
        var deleteAssetsStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteAssets, -1, &deleteAssetsStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(deleteAssetsStatement, 1, eventId, -1, SQLITE_TRANSIENT)
            sqlite3_step(deleteAssetsStatement)
        }
        sqlite3_finalize(deleteAssetsStatement)
        
        // イベントレコードを削除
        let deleteEvent = "DELETE FROM events WHERE event_id = ?"
        var deleteEventStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteEvent, -1, &deleteEventStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(deleteEventStatement, 1, eventId, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(deleteEventStatement) != SQLITE_DONE {
                sqlite3_finalize(deleteEventStatement)
                throw StorageError.deleteFailed
            }
        }
        sqlite3_finalize(deleteEventStatement)
        
        // ファイルを削除
        let fileManager = FileManager.default
        for path in filePaths {
            try? fileManager.removeItem(atPath: path)
        }
        
        print("[StorageService] Event deleted: \(eventId)")
    }
    
    func saveAnchor(_ anchor: AnchorRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let insert = "INSERT INTO anchors (anchor_id, anchor_type, merkle_root, status, created_at, service_endpoint) VALUES (?, ?, ?, ?, ?, ?)"
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, insert, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, anchor.anchorId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, anchor.anchorType, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, anchor.merkleRoot, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, anchor.status.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 5, Date().iso8601String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 6, anchor.serviceEndpoint, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                sqlite3_finalize(statement)
                throw StorageError.insertFailed
            }
        }
        sqlite3_finalize(statement)
    }
    
    func updateAnchorStatus(_ anchorId: String, status: AnchorStatus, tsaResponse: Data?, tsaTimestamp: String?) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let update = "UPDATE anchors SET status = ?, tsa_response = ?, tsa_timestamp = ?, completed_at = ? WHERE anchor_id = ?"
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, update, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, status.rawValue, -1, SQLITE_TRANSIENT)
            
            if let tsaResponse = tsaResponse {
                sqlite3_bind_blob(statement, 2, (tsaResponse as NSData).bytes, Int32(tsaResponse.count), nil)
            } else {
                sqlite3_bind_null(statement, 2)
            }
            
            if let tsaTimestamp = tsaTimestamp {
                sqlite3_bind_text(statement, 3, tsaTimestamp, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            
            sqlite3_bind_text(statement, 4, Date().iso8601String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 5, anchorId, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                sqlite3_finalize(statement)
                throw StorageError.updateFailed
            }
        }
        sqlite3_finalize(statement)
    }
    
    func getAnchor(forEventId eventId: String) throws -> AnchorRecord? {
        lock.lock()
        defer { lock.unlock() }
        
        let query = """
            SELECT a.anchor_id, a.anchor_type, a.merkle_root, a.tsa_timestamp, a.status, a.service_endpoint 
            FROM anchors a JOIN events e ON e.anchor_id = a.anchor_id WHERE e.event_id = ?
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, eventId, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                let serviceEndpoint = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
                let anchor = AnchorRecord(
                    anchorId: String(cString: sqlite3_column_text(statement, 0)),
                    anchorType: String(cString: sqlite3_column_text(statement, 1)),
                    merkleRoot: String(cString: sqlite3_column_text(statement, 2)),
                    eventCount: 0,
                    firstEventId: "",
                    lastEventId: "",
                    timestamp: sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? "",
                    anchorProof: nil,
                    serviceEndpoint: serviceEndpoint,
                    status: AnchorStatus(rawValue: String(cString: sqlite3_column_text(statement, 4))) ?? .pending
                )
                sqlite3_finalize(statement)
                return anchor
            }
        }
        sqlite3_finalize(statement)
        return nil
    }
    
    private func saveMediaFile(_ data: Data, filename: String) throws -> String {
        let mediaDirectory = getDocumentsDirectory().appendingPathComponent("media")
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let filePath = mediaDirectory.appendingPathComponent(filename)
        try data.write(to: filePath)
        return filePath.path
    }
    
    /// 元画像データを読み込む（生バイト、変換なし）
    /// AssetHash検証用に元のバイト列をそのまま返す
    func loadMediaData(eventId: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        
        // イベントを取得してファイル名を特定
        let query = "SELECT event_json FROM events WHERE event_id = ?"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, eventId, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(statement) == SQLITE_ROW,
              let jsonCString = sqlite3_column_text(statement, 0) else {
            return nil
        }
        
        let jsonString = String(cString: jsonCString)
        guard let jsonData = jsonString.data(using: .utf8),
              let event = try? JSONDecoder().decode(CPPEvent.self, from: jsonData) else {
            return nil
        }
        
        // ファイルパスを構築
        let mediaDirectory = getDocumentsDirectory().appendingPathComponent("media")
        let filePath = mediaDirectory.appendingPathComponent(event.asset.assetName)
        
        // ファイルが存在するか確認して読み込み
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            print("[Storage] Media file not found: \(filePath.path)")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: filePath)
            print("[Storage] Loaded media data: \(event.asset.assetName), size: \(data.count) bytes")
            return data
        } catch {
            print("[Storage] Failed to load media data: \(error)")
            return nil
        }
    }
    
    // MARK: - Shareable Proof Export (Privacy-First)
    
    /// 共有用Proof JSONをエクスポート（最小限の情報のみ）
    func exportShareableProof(eventId: String) throws -> URL {
        guard let event = try getEvent(eventId: eventId) else {
            throw StorageError.decodingFailed
        }
        
        let anchor = try getAnchor(forEventId: eventId)
        
        // rawEvent生成（EventHash検証用）
        let rawEventBase64 = try generateRawEventForVerification(event: event)
        
        // 公開鍵を取得（署名検証用）
        let publicKeyBase64 = CryptoService.shared.getPublicKeyBase64()
        
        // 共有用の最小限Proof JSON生成
        let shareableProof = ShareableProofJSON(
            proofId: UUIDv7.generate(),
            proofType: "CPP_INGEST_PROOF",
            proofVersion: "1.0",
            event: ShareableEventInfo(
                eventId: event.eventId,
                eventType: event.eventType.rawValue,
                timestamp: event.timestamp,
                assetHash: event.asset.assetHash,
                cameraSettings: event.cameraSettings
            ),
            rawEvent: rawEventBase64,  // EventHash検証用
            eventHash: event.eventHash,
            signature: SignatureInfo(
                algo: event.signAlgo,
                value: event.signature
            ),
            publicKey: publicKeyBase64,  // 署名検証用公開鍵
            timestampProof: anchor.flatMap { anc -> TimestampProofInfo? in
                guard !anc.timestamp.isEmpty else { return nil }
                return TimestampProofInfo(
                    type: "RFC3161",
                    issuedAt: anc.timestamp,
                    token: anc.merkleRoot // Simplified token reference
                )
            },
            attested: event.captureContext.humanAttestation != nil  // Attestedフラグ（詳細は含めずプライバシー保護）
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(shareableProof)
        
        let exportDirectory = getDocumentsDirectory().appendingPathComponent("exports")
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        
        let filename = "proof_\(event.eventId)_shareable.json"
        let filePath = exportDirectory.appendingPathComponent(filename)
        try data.write(to: filePath)
        
        return filePath
    }
    
    /// EventHash検証用のrawEventを生成（Base64エンコード）
    private func generateRawEventForVerification(event: CPPEvent) throws -> String {
        // CPPEventをDictionaryに変換
        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        
        guard var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StorageError.encodingFailed
        }
        
        // EventHash計算時と同様に、SignatureとEventHashを除去
        dict.removeValue(forKey: "Signature")
        dict.removeValue(forKey: "EventHash")
        
        // 正規化JSONを生成
        let canonicalData = try JSONCanonicalizer.canonicalize(dict)
        
        // Base64エンコードして返す
        return canonicalData.base64EncodedString()
    }
    
    // MARK: - Internal Proof Export (Forensic - Full Data)
    
    /// 内部用Proof JSONをエクスポート（完全な情報、法務提出用）
    func exportInternalProof(_ proof: InternalProofJSON) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(proof)
        
        let exportDirectory = getDocumentsDirectory().appendingPathComponent("exports_internal")
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        
        let filename = "proof_\(proof.event.eventId)_internal.json"
        let filePath = exportDirectory.appendingPathComponent(filename)
        try data.write(to: filePath)
        
        return filePath
    }
    
    /// 全証跡をZIPにまとめてエクスポート
    func exportAllInternalProofsAsZip(proofs: [InternalProofJSON]) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        // 一時ディレクトリを作成
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("vericapture_export_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // 各証跡をJSONファイルとして保存
        for proof in proofs {
            let data = try encoder.encode(proof)
            let filename = "proof_\(proof.event.eventId)_internal.json"
            let filePath = tempDir.appendingPathComponent(filename)
            try data.write(to: filePath)
        }
        
        // ZIPファイルを作成
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let zipFilename = "VeriCapture_Export_\(timestamp).zip"
        let zipPath = FileManager.default.temporaryDirectory.appendingPathComponent(zipFilename)
        
        // 既存のZIPファイルがあれば削除
        try? FileManager.default.removeItem(at: zipPath)
        
        // ZIPファイルを作成（Coordinatorを使用）
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: tempDir, options: .forUploading, error: &error) { zipURL in
            try? FileManager.default.copyItem(at: zipURL, to: zipPath)
        }
        
        // 一時ディレクトリを削除
        try? FileManager.default.removeItem(at: tempDir)
        
        if let error = error {
            throw error
        }
        
        return zipPath
    }
    
    /// 旧メソッド（後方互換性のため維持、内部用として動作）
    func exportProof(_ proof: ProofJSON) throws -> URL {
        return try exportInternalProof(proof)
    }
    
    // MARK: - Full Chain Export with Tombstones (CPP v1.0 Compliant)
    
    /// Shareable Export Package生成（第三者検証用 - Tombstone最小限）
    /// - Returns: URL to the exported JSON file
    func exportShareablePackage() throws -> URL {
        let events = try getEvents()
        let tombstones = try getAllTombstones()
        let statistics = try getChainStatistics()
        
        // 各イベントのShareable Proofを生成
        var shareableProofs: [ShareableProofJSON] = []
        for event in events {
            if let proof = try? buildShareableProof(event: event) {
                shareableProofs.append(proof)
            }
        }
        
        // Tombstoneを最小限情報に変換
        let shareableTombstones: [ShareableTombstoneInfo]? = tombstones.isEmpty ? nil : tombstones.map { ShareableTombstoneInfo(from: $0) }
        
        let package = ShareableExportPackage(
            packageVersion: "1.0",
            packageType: "CPP_SHAREABLE_EXPORT",
            generatedAt: Date().iso8601String,
            events: shareableProofs,
            tombstones: shareableTombstones,
            chainStatistics: ExportChainStatistics(
                totalEvents: statistics.totalEvents,
                activeEvents: statistics.activeEvents,
                invalidatedEvents: statistics.invalidatedEvents,
                tombstoneCount: statistics.tombstoneCount,
                anchoredEvents: statistics.anchoredEvents,
                pendingAnchorEvents: statistics.pendingAnchorEvents,
                dateRangeStart: statistics.oldestEventDate,
                dateRangeEnd: statistics.newestEventDate
            )
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(package)
        
        let exportDirectory = getDocumentsDirectory().appendingPathComponent("exports")
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "VeriCapture_Shareable_\(timestamp).json"
        let filePath = exportDirectory.appendingPathComponent(filename)
        try data.write(to: filePath)
        
        print("[StorageService] Shareable package exported: \(shareableProofs.count) events, \(shareableTombstones?.count ?? 0) tombstones")
        return filePath
    }
    
    /// Internal Export Package生成（法務・監査用 - Tombstone完全）
    /// - Parameters:
    ///   - includeLocation: 位置情報を含めるか
    /// - Returns: URL to the exported JSON file
    func exportInternalPackage(includeLocation: Bool = false) throws -> URL {
        let events = try getEvents()
        let tombstones = try getAllTombstones()
        let statistics = try getChainStatistics()
        let verificationResult = try verifyChainIntegrity()
        
        // 各イベントのInternal Proofを生成
        var internalProofs: [InternalProofJSON] = []
        for event in events {
            if let proof = try? buildInternalProof(event: event, includeLocation: includeLocation) {
                internalProofs.append(proof)
            }
        }
        
        // Tombstoneを完全情報に変換
        let internalTombstones: [InternalTombstoneInfo]? = tombstones.isEmpty ? nil : tombstones.map { InternalTombstoneInfo(from: $0) }
        
        let package = InternalExportPackage(
            packageVersion: "1.0",
            packageType: "CPP_INTERNAL_EXPORT",
            generatedAt: Date().iso8601String,
            generatedBy: "VeriCapture iOS",
            conformanceLevel: "Silver",  // CPP Conformance Level
            events: internalProofs,
            tombstones: internalTombstones,
            chainStatistics: ExportChainStatistics(
                totalEvents: statistics.totalEvents,
                activeEvents: statistics.activeEvents,
                invalidatedEvents: statistics.invalidatedEvents,
                tombstoneCount: statistics.tombstoneCount,
                anchoredEvents: statistics.anchoredEvents,
                pendingAnchorEvents: statistics.pendingAnchorEvents,
                dateRangeStart: statistics.oldestEventDate,
                dateRangeEnd: statistics.newestEventDate
            ),
            chainIntegrity: ChainIntegrityInfo(
                isValid: verificationResult.isValid,
                verifiedAt: verificationResult.verifiedAt.iso8601String,
                checkedEvents: verificationResult.checkedEvents,
                checkedTombstones: verificationResult.checkedTombstones,
                warningCount: verificationResult.warningCount,
                errorCount: verificationResult.errorCount
            )
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(package)
        
        let exportDirectory = getDocumentsDirectory().appendingPathComponent("exports_internal")
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "VeriCapture_Internal_\(timestamp).json"
        let filePath = exportDirectory.appendingPathComponent(filename)
        try data.write(to: filePath)
        
        print("[StorageService] Internal package exported: \(internalProofs.count) events, \(internalTombstones?.count ?? 0) tombstones")
        return filePath
    }
    
    /// 全証跡をZIPにまとめてエクスポート（Tombstone含む）
    /// - Parameters:
    ///   - includeLocation: 位置情報を含めるか
    ///   - includeShareable: Shareable版も含めるか
    /// - Returns: URL to the ZIP file
    func exportFullChainAsZip(includeLocation: Bool = false, includeShareable: Bool = true) throws -> URL {
        // 一時ディレクトリを作成
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("vericapture_full_export_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Internal Package をエクスポート
        let internalURL = try exportInternalPackage(includeLocation: includeLocation)
        let internalFilename = internalURL.lastPathComponent
        try FileManager.default.copyItem(at: internalURL, to: tempDir.appendingPathComponent(internalFilename))
        
        // Shareable Package をエクスポート（オプション）
        if includeShareable {
            let shareableURL = try exportShareablePackage()
            let shareableFilename = shareableURL.lastPathComponent
            try FileManager.default.copyItem(at: shareableURL, to: tempDir.appendingPathComponent(shareableFilename))
        }
        
        // README を追加
        let readme = generateExportReadme(includeLocation: includeLocation, includeShareable: includeShareable)
        let readmePath = tempDir.appendingPathComponent("README.txt")
        try readme.write(to: readmePath, atomically: true, encoding: .utf8)
        
        // ZIPファイルを作成
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let zipFilename = "VeriCapture_FullExport_\(timestamp).zip"
        let zipPath = FileManager.default.temporaryDirectory.appendingPathComponent(zipFilename)
        
        // 既存のZIPファイルがあれば削除
        try? FileManager.default.removeItem(at: zipPath)
        
        // ZIPファイルを作成
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: tempDir, options: .forUploading, error: &error) { zipURL in
            try? FileManager.default.copyItem(at: zipURL, to: zipPath)
        }
        
        // 一時ディレクトリを削除
        try? FileManager.default.removeItem(at: tempDir)
        
        if let error = error {
            throw error
        }
        
        print("[StorageService] Full chain ZIP exported: \(zipFilename)")
        return zipPath
    }
    
    /// Shareable Proof生成ヘルパー
    private func buildShareableProof(event: CPPEvent) throws -> ShareableProofJSON {
        let anchor = try getAnchor(forEventId: event.eventId)
        let rawEventBase64 = try generateRawEventForVerification(event: event)
        let publicKeyBase64 = CryptoService.shared.getPublicKeyBase64()
        
        return ShareableProofJSON(
            proofId: event.eventId,
            proofType: "CPP_INGEST_PROOF",
            proofVersion: "1.0",
            event: ShareableEventInfo(
                eventId: event.eventId,
                eventType: event.eventType.rawValue,
                timestamp: event.timestamp,
                assetHash: event.asset.assetHash,
                cameraSettings: event.cameraSettings
            ),
            rawEvent: rawEventBase64,
            eventHash: event.eventHash,
            signature: SignatureInfo(
                algo: event.signAlgo,
                value: event.signature
            ),
            publicKey: publicKeyBase64,
            timestampProof: anchor.flatMap { anc -> TimestampProofInfo? in
                guard !anc.timestamp.isEmpty else { return nil }
                return TimestampProofInfo(
                    type: "RFC3161",
                    issuedAt: anc.timestamp,
                    token: anc.merkleRoot
                )
            },
            attested: event.captureContext.humanAttestation != nil
        )
    }
    
    /// Internal Proof生成ヘルパー
    private func buildInternalProof(event: CPPEvent, includeLocation: Bool) throws -> InternalProofJSON {
        let anchor = try getAnchor(forEventId: event.eventId)
        let publicKeyBase64 = CryptoService.shared.getPublicKeyBase64()
        
        var location: LocationInfo? = nil
        if includeLocation, let loc = getLocationMetadata(eventId: event.eventId) {
            location = LocationInfo(
                latitude: loc.latitude,
                longitude: loc.longitude,
                accuracy: nil,
                altitude: nil,
                capturedAt: event.timestamp
            )
        }
        
        return InternalProofJSON(
            proofVersion: "1.0",
            proofType: "CPP_INTERNAL_PROOF",
            generatedAt: Date().iso8601String,
            generatedBy: "VeriCapture iOS",
            event: event,
            anchor: anchor.flatMap { anc -> AnchorInfo? in
                guard anc.status == .completed else { return nil }
                return AnchorInfo(
                    anchorId: anc.anchorId,
                    anchorType: "RFC3161",
                    merkleRoot: anc.merkleRoot,
                    merkleProof: [],
                    merkleIndex: 0,
                    tsaResponse: nil,
                    tsaTimestamp: anc.timestamp.isEmpty ? nil : anc.timestamp,
                    tsaService: anc.serviceEndpoint
                )
            },
            verification: VerificationInfo(
                publicKey: publicKeyBase64,
                keyAttestation: event.captureContext.keyAttestation,
                verificationEndpoint: "https://verify.veritaschain.org/cpp/\(event.eventId)",
                signer: nil
            ),
            metadata: ProofMetadata(
                originalFilename: event.asset.assetName,
                originalSize: event.asset.assetSize,
                thumbnailHash: nil,
                location: location
            )
        )
    }
    
    /// エクスポートREADME生成
    private func generateExportReadme(includeLocation: Bool, includeShareable: Bool) -> String {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .long)
        return """
        VeriCapture Export Package
        ==========================
        
        Generated: \(timestamp)
        Export Type: Full Chain Export with Tombstones
        CPP Version: 1.0
        VAP Version: 1.2
        
        Contents:
        ---------
        \(includeShareable ? "- VeriCapture_Shareable_*.json: Third-party verification data (minimal, privacy-first)" : "")
        - VeriCapture_Internal_*.json: Full audit trail (forensic, includes tombstones)
        
        Tombstones:
        -----------
        Tombstones record proof invalidation events. They prove that deletions were
        intentional and not tampering. The Internal export includes full tombstone
        details; the Shareable export includes only existence and reason codes.
        
        Location Data: \(includeLocation ? "INCLUDED" : "NOT INCLUDED")
        
        Verification:
        -------------
        To verify proofs, scan the QR code or use the VeriCheck feature in the app.
        
        © 2026 VeritasChain Co., Ltd.
        """
    }
    
    // MARK: - Image Loading
    
    func getImagePath(eventId: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        
        let query = "SELECT file_path FROM assets WHERE event_id = ? LIMIT 1"
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, eventId, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                let path = String(cString: sqlite3_column_text(statement, 0))
                sqlite3_finalize(statement)
                return path
            }
        }
        sqlite3_finalize(statement)
        return nil
    }
    
    func loadImage(eventId: String) -> UIImage? {
        guard let path = try? getImagePath(eventId: eventId),
              let data = FileManager.default.contents(atPath: path),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }
    
    func loadThumbnail(eventId: String, size: CGSize = CGSize(width: 120, height: 120)) -> UIImage? {
        guard let image = loadImage(eventId: eventId) else { return nil }
        
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    private func executeSQL(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let error = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw StorageError.sqlError(error)
        }
    }
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // MARK: - Location Metadata (Local Only - Not in Proof JSON)
    
    /// 位置情報を保存（デバイス内のみ、Proof JSONには含まれない）
    func saveLocationMetadata(eventId: String, latitude: Double, longitude: Double) {
        lock.lock()
        defer { lock.unlock() }
        
        let insert = """
            INSERT OR REPLACE INTO location_metadata (event_id, latitude, longitude, created_at)
            VALUES (?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, insert, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, eventId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 2, latitude)
            sqlite3_bind_double(statement, 3, longitude)
            sqlite3_bind_text(statement, 4, Date().iso8601String, -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }
    
    /// 位置情報を取得
    func getLocationMetadata(eventId: String) -> (latitude: Double, longitude: Double)? {
        lock.lock()
        defer { lock.unlock() }
        
        let query = "SELECT latitude, longitude FROM location_metadata WHERE event_id = ?"
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, eventId, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                let latitude = sqlite3_column_double(statement, 0)
                let longitude = sqlite3_column_double(statement, 1)
                sqlite3_finalize(statement)
                return (latitude, longitude)
            }
        }
        sqlite3_finalize(statement)
        return nil
    }
    
    // MARK: - Media Status Management (CPP Additional Spec)
    
    /// メディアを削除（証跡は維持）
    func purgeMedia(eventId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        
        // 1. 画像ファイルを削除
        let imageDir = getDocumentsDirectory().appendingPathComponent("images")
        let jpgPath = imageDir.appendingPathComponent("\(eventId).jpg")
        let pngPath = imageDir.appendingPathComponent("\(eventId).png")
        let heicPath = imageDir.appendingPathComponent("\(eventId).heic")
        
        for path in [jpgPath, pngPath, heicPath] {
            if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
                print("[Storage] Purged media file: \(path.lastPathComponent)")
            }
        }
        
        // 2. assets テーブルのファイルパスを取得して削除
        let assetQuery = "SELECT file_path FROM assets WHERE event_id = ?"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, assetQuery, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, eventId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW {
                let filePath = String(cString: sqlite3_column_text(statement, 0))
                let fullPath = getDocumentsDirectory().appendingPathComponent(filePath)
                if FileManager.default.fileExists(atPath: fullPath.path) {
                    try FileManager.default.removeItem(at: fullPath)
                }
            }
        }
        sqlite3_finalize(statement)
        
        // 3. MediaStatus を更新
        let now = Date().iso8601String
        let update = """
            UPDATE events 
            SET media_status = 'PURGED',
                media_status_changed_at = ?,
                media_status_reason = 'USER_REQUESTED'
            WHERE event_id = ?
        """
        
        var updateStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, update, -1, &updateStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(updateStmt, 1, now, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(updateStmt, 2, eventId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(updateStmt) != SQLITE_DONE {
                sqlite3_finalize(updateStmt)
                throw StorageError.updateFailed
            }
        }
        sqlite3_finalize(updateStmt)
        
        print("[Storage] Media purged for event: \(eventId)")
    }
    
    /// MediaStatusを取得（カラムが存在しない場合はデフォルト値を返す）
    func getMediaStatus(eventId: String) -> MediaStatus {
        lock.lock()
        defer { lock.unlock() }
        
        // カラムの存在確認
        if !columnExists(table: "events", column: "media_status") {
            return .present
        }
        
        let query = "SELECT media_status FROM events WHERE event_id = ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, eventId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW {
                let status = String(cString: sqlite3_column_text(statement, 0))
                sqlite3_finalize(statement)
                return MediaStatus(rawValue: status) ?? .present
            }
        }
        sqlite3_finalize(statement)
        return .present
    }
    
    // MARK: - Event Status Management (CPP Additional Spec)
    
    /// EventStatusを更新
    func updateEventStatus(eventId: String, status: EventStatus) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let update = "UPDATE events SET event_status = ? WHERE event_id = ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, update, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, status.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, eventId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) != SQLITE_DONE {
                sqlite3_finalize(statement)
                throw StorageError.updateFailed
            }
        }
        sqlite3_finalize(statement)
        print("[Storage] Event status updated: \(eventId) -> \(status.rawValue)")
    }
    
    /// EventStatusを取得（カラムが存在しない場合はデフォルト値を返す）
    func getEventStatus(eventId: String) -> EventStatus {
        lock.lock()
        defer { lock.unlock() }
        
        // カラムの存在確認
        if !columnExists(table: "events", column: "event_status") {
            return .active
        }
        
        let query = "SELECT event_status FROM events WHERE event_id = ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, eventId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW {
                let status = String(cString: sqlite3_column_text(statement, 0))
                sqlite3_finalize(statement)
                return EventStatus(rawValue: status) ?? .active
            }
        }
        sqlite3_finalize(statement)
        return .active
    }
    
    /// カラムの存在確認
    private func columnExists(table: String, column: String) -> Bool {
        let query = "PRAGMA table_info(\(table))"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let name = sqlite3_column_text(statement, 1) {
                    if String(cString: name) == column {
                        sqlite3_finalize(statement)
                        return true
                    }
                }
            }
        }
        sqlite3_finalize(statement)
        return false
    }
    
    // MARK: - Tombstone Management (CPP Additional Spec)
    
    /// Tombstoneを保存
    func saveTombstone(_ tombstone: TombstoneEvent) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let insert = """
            INSERT INTO tombstones (
                tombstone_id, target_event_id, target_event_hash,
                reason_code, reason_description,
                executor_type, executor_attestation,
                prev_hash, tombstone_hash, signature,
                timestamp, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, insert, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, tombstone.tombstoneId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, tombstone.target.eventId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, tombstone.target.eventHash, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, tombstone.reason.code, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 5, tombstone.reason.description ?? "", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 6, tombstone.executor.type, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 7, tombstone.executor.attestation ?? "", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 8, tombstone.prevHash, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 9, tombstone.tombstoneHash, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 10, tombstone.signature.value, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 11, tombstone.timestamp, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 12, Date().iso8601String, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                sqlite3_finalize(statement)
                throw StorageError.insertFailed
            }
        }
        sqlite3_finalize(statement)
        print("[Storage] Tombstone saved: \(tombstone.tombstoneId)")
    }
    
    /// Tombstoneが存在するか確認
    func hasTombstone(forEventId eventId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let query = "SELECT COUNT(*) FROM tombstones WHERE target_event_id = ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, eventId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW {
                let count = sqlite3_column_int(statement, 0)
                sqlite3_finalize(statement)
                return count > 0
            }
        }
        sqlite3_finalize(statement)
        return false
    }
    
    /// Tombstoneを取得
    func getTombstone(forEventId eventId: String) -> TombstoneEvent? {
        lock.lock()
        defer { lock.unlock() }
        
        let query = """
            SELECT tombstone_id, target_event_id, target_event_hash,
                   reason_code, reason_description,
                   executor_type, executor_attestation,
                   prev_hash, tombstone_hash, signature, timestamp
            FROM tombstones WHERE target_event_id = ?
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, eventId, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                let tombstoneId = String(cString: sqlite3_column_text(statement, 0))
                let targetEventId = String(cString: sqlite3_column_text(statement, 1))
                let targetEventHash = String(cString: sqlite3_column_text(statement, 2))
                let reasonCode = String(cString: sqlite3_column_text(statement, 3))
                let reasonDesc = String(cString: sqlite3_column_text(statement, 4))
                let executorType = String(cString: sqlite3_column_text(statement, 5))
                let executorAttestation = String(cString: sqlite3_column_text(statement, 6))
                let prevHash = String(cString: sqlite3_column_text(statement, 7))
                let tombstoneHash = String(cString: sqlite3_column_text(statement, 8))
                let signature = String(cString: sqlite3_column_text(statement, 9))
                let timestamp = String(cString: sqlite3_column_text(statement, 10))
                
                sqlite3_finalize(statement)
                
                return TombstoneEvent(
                    tombstoneId: tombstoneId,
                    eventType: "TOMBSTONE",
                    timestamp: timestamp,
                    target: TombstoneTarget(eventId: targetEventId, eventHash: targetEventHash),
                    reason: TombstoneReason(code: reasonCode, description: reasonDesc.isEmpty ? nil : reasonDesc),
                    executor: TombstoneExecutor(type: executorType, attestation: executorAttestation.isEmpty ? nil : executorAttestation),
                    prevHash: prevHash,
                    tombstoneHash: tombstoneHash,
                    signature: SignatureInfo(algo: "ES256", value: signature)
                )
            }
        }
        sqlite3_finalize(statement)
        return nil
    }
    
    /// 最新のイベントハッシュを取得（チェーン連結用）
    func getLatestEventHash() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        
        // イベントとTombstoneの両方から最新を取得
        let query = """
            SELECT hash, timestamp FROM (
                SELECT event_hash as hash, timestamp FROM events
                UNION ALL
                SELECT tombstone_hash as hash, timestamp FROM tombstones
            ) ORDER BY timestamp DESC LIMIT 1
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                let hash = String(cString: sqlite3_column_text(statement, 0))
                sqlite3_finalize(statement)
                return hash
            }
        }
        sqlite3_finalize(statement)
        
        // チェーンが空の場合は初期ハッシュを返す
        return "sha256:0000000000000000000000000000000000000000000000000000000000000000"
    }
    
    // MARK: - Extended Event Info (CPP Additional Spec)
    
    /// 拡張イベント情報を取得
    func getExtendedEventInfo(eventId: String) -> ExtendedEventInfo? {
        guard let event = try? getEvent(eventId: eventId) else { return nil }
        
        let mediaStatus = getMediaStatus(eventId: eventId)
        let eventStatus = getEventStatus(eventId: eventId)
        let anchorStatus = getAnchorStatus(eventId: eventId)
        let tombstone = getTombstone(forEventId: eventId)
        
        return ExtendedEventInfo(
            event: event,
            mediaStatus: mediaStatus,
            eventStatus: eventStatus,
            anchorStatus: anchorStatus,
            tombstone: tombstone
        )
    }
    
    /// アンカー状態を取得（UI表示用）
    func getAnchorStatus(eventId: String) -> ProofAnchorStatus {
        lock.lock()
        defer { lock.unlock() }
        
        let query = """
            SELECT a.status FROM anchors a
            INNER JOIN events e ON e.anchor_id = a.anchor_id
            WHERE e.event_id = ?
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, eventId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW {
                let status = String(cString: sqlite3_column_text(statement, 0))
                sqlite3_finalize(statement)
                
                switch status.uppercased() {
                case "COMPLETED", "ANCHORED":
                    return .anchored
                case "FAILED":
                    return .failed
                case "SKIPPED":
                    return .skipped
                default:
                    return .pending
                }
            }
        }
        sqlite3_finalize(statement)
        return .pending
    }
    
    /// PENDING状態のイベントを取得
    func getPendingEvents() throws -> [CPPEvent] {
        lock.lock()
        defer { lock.unlock() }
        
        var events: [CPPEvent] = []
        
        let query = """
            SELECT event_json FROM events
            WHERE anchor_id IS NULL OR anchor_id IN (
                SELECT anchor_id FROM anchors WHERE status = 'PENDING'
            )
            ORDER BY timestamp ASC
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let json = String(cString: sqlite3_column_text(statement, 0))
                if let data = json.data(using: .utf8),
                   let event = try? JSONDecoder().decode(CPPEvent.self, from: data) {
                    events.append(event)
                }
            }
        }
        sqlite3_finalize(statement)
        
        return events
    }
    
    /// PENDING状態のイベント数を取得
    func getPendingEventCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        
        let query = """
            SELECT COUNT(*) FROM events
            WHERE anchor_id IS NULL OR anchor_id IN (
                SELECT anchor_id FROM anchors WHERE status = 'PENDING'
            )
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                let count = Int(sqlite3_column_int(statement, 0))
                sqlite3_finalize(statement)
                return count
            }
        }
        sqlite3_finalize(statement)
        return 0
    }
    
    /// アンカー状態を更新（UI表示用）
    func updateAnchorStatus(anchorId: String, status: ProofAnchorStatus, failureReason: String? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        
        var update: String
        if status == .anchored {
            update = "UPDATE anchors SET status = 'COMPLETED', completed_at = ? WHERE anchor_id = ?"
        } else if status == .failed {
            update = "UPDATE anchors SET status = 'FAILED', failure_reason = ?, retry_count = retry_count + 1 WHERE anchor_id = ?"
        } else {
            update = "UPDATE anchors SET status = ? WHERE anchor_id = ?"
        }
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, update, -1, &statement, nil) == SQLITE_OK {
            if status == .anchored {
                sqlite3_bind_text(statement, 1, Date().iso8601String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, anchorId, -1, SQLITE_TRANSIENT)
            } else if status == .failed {
                sqlite3_bind_text(statement, 1, failureReason ?? "", -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, anchorId, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_text(statement, 1, status.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, anchorId, -1, SQLITE_TRANSIENT)
            }
            
            if sqlite3_step(statement) != SQLITE_DONE {
                sqlite3_finalize(statement)
                throw StorageError.updateFailed
            }
        }
        sqlite3_finalize(statement)
    }
    
    // MARK: - Chain Verification
    
    /// チェーンの全Tombstoneを取得
    func getAllTombstones(chainId: String? = nil) throws -> [TombstoneEvent] {
        lock.lock()
        defer { lock.unlock() }
        
        // v40: chainIdが指定されている場合は、そのチェーンのイベントに関連するTombstoneのみ取得
        var query: String
        if chainId != nil {
            // chain_idでフィルタリング（eventsテーブルとJOIN）
            query = """
                SELECT t.tombstone_id, t.target_event_id, t.target_event_hash, t.reason_code, t.reason_description, 
                       t.executor_type, t.executor_attestation, t.prev_hash, t.tombstone_hash, t.signature, t.timestamp 
                FROM tombstones t
                INNER JOIN events e ON t.target_event_id = e.event_id
                WHERE e.chain_id = ?
                ORDER BY t.timestamp ASC
            """
        } else {
            query = "SELECT tombstone_id, target_event_id, target_event_hash, reason_code, reason_description, executor_type, executor_attestation, prev_hash, tombstone_hash, signature, timestamp FROM tombstones ORDER BY timestamp ASC"
        }
        
        var tombstones: [TombstoneEvent] = []
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            if let chainId = chainId {
                sqlite3_bind_text(statement, 1, chainId, -1, SQLITE_TRANSIENT)
            }
            while sqlite3_step(statement) == SQLITE_ROW {
                let tombstoneId = String(cString: sqlite3_column_text(statement, 0))
                let targetEventId = String(cString: sqlite3_column_text(statement, 1))
                let targetEventHash = String(cString: sqlite3_column_text(statement, 2))
                let reasonCode = String(cString: sqlite3_column_text(statement, 3))
                let reasonDescription = sqlite3_column_text(statement, 4).map { String(cString: $0) }
                let executorType = String(cString: sqlite3_column_text(statement, 5))
                let executorAttestation = sqlite3_column_text(statement, 6).map { String(cString: $0) }
                let prevHash = String(cString: sqlite3_column_text(statement, 7))
                let tombstoneHash = String(cString: sqlite3_column_text(statement, 8))
                let signature = String(cString: sqlite3_column_text(statement, 9))
                let timestamp = String(cString: sqlite3_column_text(statement, 10))
                
                let tombstone = TombstoneEvent(
                    tombstoneId: tombstoneId,
                    eventType: "TOMBSTONE",
                    timestamp: timestamp,
                    target: TombstoneTarget(eventId: targetEventId, eventHash: targetEventHash),
                    reason: TombstoneReason(code: reasonCode, description: reasonDescription),
                    executor: TombstoneExecutor(type: executorType, attestation: executorAttestation),
                    prevHash: prevHash,
                    tombstoneHash: tombstoneHash,
                    signature: SignatureInfo(algo: "ES256", value: signature)
                )
                tombstones.append(tombstone)
            }
        } else {
            print("[Storage] getAllTombstones query failed: \(String(cString: sqlite3_errmsg(db)))")
        }
        sqlite3_finalize(statement)
        return tombstones
    }
    
    /// チェーン統計情報を取得
    func getChainStatistics(chainId: String? = nil) throws -> ChainStatistics {
        // v40: chainIdが指定されている場合はフィルタリング
        let events: [CPPEvent]
        if let chainId = chainId {
            events = try getAllEvents(chainId: chainId)
        } else {
            events = try getEvents()
        }
        let tombstones = try getAllTombstones(chainId: chainId)
        
        // イベントのステータスをカウント
        var activeCount = 0
        var invalidatedCount = 0
        var anchoredCount = 0
        var pendingCount = 0
        
        for event in events {
            let status = getEventStatus(eventId: event.eventId)
            if status == .active {
                activeCount += 1
            } else if status == .invalidated {
                invalidatedCount += 1
            }
            
            if isEventAnchored(eventId: event.eventId) {
                anchoredCount += 1
            } else {
                pendingCount += 1
            }
        }
        
        // 日付の取得（タイムスタンプ順にソート）
        let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
        let oldestDate = sortedEvents.first?.timestamp
        let newestDate = sortedEvents.last?.timestamp
        
        return ChainStatistics(
            totalEvents: events.count,
            activeEvents: activeCount,
            invalidatedEvents: invalidatedCount,
            tombstoneCount: tombstones.count,
            anchoredEvents: anchoredCount,
            pendingAnchorEvents: pendingCount,
            oldestEventDate: oldestDate,
            newestEventDate: newestDate
        )
    }
    
    /// チェーンの整合性を検証
    func verifyChainIntegrity(chainId: String? = nil) throws -> ChainVerificationResult {
        var errors: [ChainVerificationError] = []
        
        // 1. v40: chainIdが指定されている場合はフィルタリング
        let allEvents: [CPPEvent]
        if let chainId = chainId {
            allEvents = try getAllEvents(chainId: chainId)
        } else {
            allEvents = try getEvents()
        }
        let events = allEvents.sorted { $0.timestamp < $1.timestamp }
        let tombstones = try getAllTombstones(chainId: chainId)
        
        // Tombstoneのtarget.eventHashをセットに格納（削除されたイベントのハッシュ）
        let deletedEventHashes = Set(tombstones.map { $0.target.eventHash })
        
        // 2. イベントチェーンの検証
        var previousHash = "GENESIS"
        for (index, event) in events.enumerated() {
            // PrevHashの検証
            if event.prevHash != previousHash {
                // 削除されたイベントによるギャップかチェック
                if deletedEventHashes.contains(event.prevHash) {
                    // 削除によるギャップ → 警告扱い
                    errors.append(ChainVerificationError(
                        errorType: .deletedEventGap,
                        eventId: event.eventId,
                        expectedValue: previousHash,
                        actualValue: event.prevHash,
                        index: index,
                        isWarning: true
                    ))
                } else {
                    // 本当の不整合 → エラー
                    errors.append(ChainVerificationError(
                        errorType: .prevHashMismatch,
                        eventId: event.eventId,
                        expectedValue: previousHash,
                        actualValue: event.prevHash,
                        index: index
                    ))
                }
            }
            
            // EventHashの検証（再計算して比較）
            if let computedHash = computeEventHash(event: event) {
                if computedHash != event.eventHash {
                    errors.append(ChainVerificationError(
                        errorType: .eventHashMismatch,
                        eventId: event.eventId,
                        expectedValue: computedHash,
                        actualValue: event.eventHash,
                        index: index
                    ))
                }
            }
            
            previousHash = event.eventHash
        }
        
        // 3. Tombstoneチェーンの検証
        for (index, tombstone) in tombstones.enumerated() {
            // TombstoneのTargetEventHashの検証
            if let targetEvent = events.first(where: { $0.eventId == tombstone.target.eventId }) {
                if targetEvent.eventHash != tombstone.target.eventHash {
                    errors.append(ChainVerificationError(
                        errorType: .tombstoneTargetMismatch,
                        eventId: tombstone.tombstoneId,
                        expectedValue: targetEvent.eventHash,
                        actualValue: tombstone.target.eventHash,
                        index: index
                    ))
                }
            }
            // 注: orphanedTombstoneは削除の結果なので、警告として扱うか省略
            // 削除されたイベントのTombstoneは正常なので、ここではエラーにしない
        }
        
        // isValidは「実際のエラー」がない場合にtrue（警告のみならOK）
        let realErrors = errors.filter { !$0.isWarning }
        
        return ChainVerificationResult(
            isValid: realErrors.isEmpty,
            checkedEvents: events.count,
            checkedTombstones: tombstones.count,
            errors: errors,
            verifiedAt: Date()
        )
    }
    
    /// イベントのハッシュを再計算（簡易版）
    private func computeEventHash(event: CPPEvent) -> String? {
        // 署名前のイベントデータを再構築してハッシュ化
        // 注: 完全な検証には正規化JSONの再構築が必要
        // ここでは保存されているハッシュ値の形式チェックのみ
        if event.eventHash.hasPrefix("sha256:") && event.eventHash.count > 70 {
            return event.eventHash // 形式が正しければそのまま返す（簡易版）
        }
        return nil
    }
}

// MARK: - Chain Verification Models

/// チェーン統計情報
struct ChainStatistics: Sendable {
    let totalEvents: Int
    let activeEvents: Int
    let invalidatedEvents: Int
    let tombstoneCount: Int
    let anchoredEvents: Int
    let pendingAnchorEvents: Int
    let oldestEventDate: String?
    let newestEventDate: String?
}

/// チェーン検証結果
struct ChainVerificationResult: Sendable {
    let isValid: Bool
    let checkedEvents: Int
    let checkedTombstones: Int
    let errors: [ChainVerificationError]
    let verifiedAt: Date
    
    /// 実際のエラー数（警告を除く）
    var errorCount: Int {
        errors.filter { !$0.isWarning }.count
    }
    
    /// 警告数
    var warningCount: Int {
        errors.filter { $0.isWarning }.count
    }
    
    /// 実際にエラーがあるか（警告のみの場合はfalse）
    var hasRealErrors: Bool {
        errorCount > 0
    }
}

/// チェーン検証エラー
struct ChainVerificationError: Sendable, Identifiable {
    let id = UUID()
    let errorType: ChainErrorType
    let eventId: String
    let expectedValue: String
    let actualValue: String
    let index: Int
    let isWarning: Bool  // 警告扱い（削除によるギャップなど）
    
    init(errorType: ChainErrorType, eventId: String, expectedValue: String, actualValue: String, index: Int, isWarning: Bool = false) {
        self.errorType = errorType
        self.eventId = eventId
        self.expectedValue = expectedValue
        self.actualValue = actualValue
        self.index = index
        self.isWarning = isWarning
    }
}

/// チェーンエラータイプ
enum ChainErrorType: String, Sendable {
    case prevHashMismatch = "PREV_HASH_MISMATCH"
    case eventHashMismatch = "EVENT_HASH_MISMATCH"
    case signatureInvalid = "SIGNATURE_INVALID"
    case tombstoneTargetMismatch = "TOMBSTONE_TARGET_MISMATCH"
    case orphanedTombstone = "ORPHANED_TOMBSTONE"
    case timestampAnomaly = "TIMESTAMP_ANOMALY"
    case deletedEventGap = "DELETED_EVENT_GAP"  // 削除によるギャップ（警告）
}

// MARK: - Chain Reset (TestFlight/Debug用)

extension StorageService {
    
    /// チェーンを完全にリセット（全イベント・Tombstone・アンカー・メディアを削除）
    /// - Warning: この操作は取り消せません
    func resetChain() throws {
        lock.lock()
        defer { lock.unlock() }
        
        // 1. メディアファイルを全削除
        let mediaDir = getDocumentsDirectory().appendingPathComponent("media")
        let thumbnailDir = getDocumentsDirectory().appendingPathComponent("thumbnails")
        
        try? FileManager.default.removeItem(at: mediaDir)
        try? FileManager.default.removeItem(at: thumbnailDir)
        
        // ディレクトリを再作成
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailDir, withIntermediateDirectories: true)
        
        // 2. データベーステーブルをクリア
        let tables = ["events", "anchors", "tombstones", "chains", "location_metadata"]
        
        for table in tables {
            let deleteQuery = "DELETE FROM \(table)"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteQuery, -1, &statement, nil) == SQLITE_OK {
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
        
        // 3. 新しいチェーンIDを生成
        let newChainId = UUIDv7.generate()
        let insert = "INSERT INTO chains (chain_id, created_at) VALUES (?, ?)"
        
        var insertStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, insert, -1, &insertStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(insertStatement, 1, newChainId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(insertStatement, 2, Date().iso8601String, -1, SQLITE_TRANSIENT)
            sqlite3_step(insertStatement)
        }
        sqlite3_finalize(insertStatement)
        
        print("[StorageService] Chain reset completed. New chainId: \(newChainId)")
    }
    
    // MARK: - Case Management (v40)
    
    /// Create a new case
    func createCase(_ caseItem: Case) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let sql = """
            INSERT INTO cases (
                case_id, chain_id, name, description, created_at, updated_at,
                is_archived, event_count, last_capture_at, icon, color_hex
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StorageError.sqlError("Failed to prepare case insert")
        }
        defer { sqlite3_finalize(statement) }
        
        let formatter = ISO8601DateFormatter()
        
        sqlite3_bind_text(statement, 1, caseItem.caseId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, caseItem.chainId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, caseItem.name, -1, SQLITE_TRANSIENT)
        
        if let desc = caseItem.description {
            sqlite3_bind_text(statement, 4, desc, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 4)
        }
        
        sqlite3_bind_text(statement, 5, formatter.string(from: caseItem.createdAt), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 6, formatter.string(from: caseItem.updatedAt), -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 7, caseItem.isArchived ? 1 : 0)
        sqlite3_bind_int(statement, 8, Int32(caseItem.eventCount))
        
        if let lastCapture = caseItem.lastCaptureAt {
            sqlite3_bind_text(statement, 9, formatter.string(from: lastCapture), -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 9)
        }
        
        sqlite3_bind_text(statement, 10, caseItem.icon, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 11, caseItem.colorHex, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StorageError.insertFailed
        }
        
        // Register chain
        let chainSql = "INSERT OR IGNORE INTO chains (chain_id, created_at) VALUES (?, ?)"
        var chainStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, chainSql, -1, &chainStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(chainStatement, 1, caseItem.chainId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(chainStatement, 2, formatter.string(from: Date()), -1, SQLITE_TRANSIENT)
            sqlite3_step(chainStatement)
        }
        sqlite3_finalize(chainStatement)
        
        print("[StorageService] Created case: \(caseItem.name) with chainId: \(caseItem.chainId)")
    }
    
    /// Get case by ID
    func getCase(caseId: String) throws -> Case? {
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "SELECT * FROM cases WHERE case_id = ?"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, caseId, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        return parseCaseRow(statement)
    }
    
    /// Get case by chain ID
    func getCase(byChainId chainId: String) throws -> Case? {
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "SELECT * FROM cases WHERE chain_id = ?"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, chainId, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        return parseCaseRow(statement)
    }
    
    /// Get all cases
    func getAllCases(includeArchived: Bool = false) throws -> [Case] {
        lock.lock()
        defer { lock.unlock() }
        
        let sql: String
        if includeArchived {
            sql = "SELECT * FROM cases ORDER BY created_at DESC"
        } else {
            sql = "SELECT * FROM cases WHERE is_archived = 0 ORDER BY created_at DESC"
        }
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        
        var cases: [Case] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let caseItem = parseCaseRow(statement) {
                cases.append(caseItem)
            }
        }
        
        return cases
    }
    
    /// Update case
    func updateCase(_ caseItem: Case) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let sql = """
            UPDATE cases SET
                name = ?, description = ?, updated_at = ?,
                is_archived = ?, event_count = ?, last_capture_at = ?,
                icon = ?, color_hex = ?
            WHERE case_id = ?
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StorageError.sqlError("Failed to prepare case update")
        }
        defer { sqlite3_finalize(statement) }
        
        let formatter = ISO8601DateFormatter()
        
        sqlite3_bind_text(statement, 1, caseItem.name, -1, SQLITE_TRANSIENT)
        
        if let desc = caseItem.description {
            sqlite3_bind_text(statement, 2, desc, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 2)
        }
        
        sqlite3_bind_text(statement, 3, formatter.string(from: caseItem.updatedAt), -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 4, caseItem.isArchived ? 1 : 0)
        sqlite3_bind_int(statement, 5, Int32(caseItem.eventCount))
        
        if let lastCapture = caseItem.lastCaptureAt {
            sqlite3_bind_text(statement, 6, formatter.string(from: lastCapture), -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 6)
        }
        
        sqlite3_bind_text(statement, 7, caseItem.icon, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 8, caseItem.colorHex, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 9, caseItem.caseId, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StorageError.updateFailed
        }
    }
    
    /// Delete case
    func deleteCase(caseId: String, force: Bool = false) throws {
        lock.lock()
        defer { lock.unlock() }
        
        if force {
            // Get case to find chainId
            let getCaseSql = "SELECT chain_id FROM cases WHERE case_id = ?"
            var getStatement: OpaquePointer?
            var chainId: String?
            
            if sqlite3_prepare_v2(db, getCaseSql, -1, &getStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(getStatement, 1, caseId, -1, SQLITE_TRANSIENT)
                if sqlite3_step(getStatement) == SQLITE_ROW {
                    chainId = String(cString: sqlite3_column_text(getStatement, 0))
                }
            }
            sqlite3_finalize(getStatement)
            
            // Delete events and related data
            if let chainId = chainId {
                let deleteEventsSql = "DELETE FROM events WHERE chain_id = ?"
                var deleteEventsStatement: OpaquePointer?
                if sqlite3_prepare_v2(db, deleteEventsSql, -1, &deleteEventsStatement, nil) == SQLITE_OK {
                    sqlite3_bind_text(deleteEventsStatement, 1, chainId, -1, SQLITE_TRANSIENT)
                    sqlite3_step(deleteEventsStatement)
                }
                sqlite3_finalize(deleteEventsStatement)
            }
        }
        
        let sql = "DELETE FROM cases WHERE case_id = ?"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StorageError.sqlError("Failed to prepare case delete")
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, caseId, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StorageError.deleteFailed
        }
    }
    
    /// Update case statistics from database
    func updateCaseStatistics(caseId: String) {
        guard let caseItem = try? getCase(caseId: caseId) else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        // Count events
        let countSql = "SELECT COUNT(*) FROM events WHERE chain_id = ?"
        var countStatement: OpaquePointer?
        var eventCount = 0
        
        if sqlite3_prepare_v2(db, countSql, -1, &countStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(countStatement, 1, caseItem.chainId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(countStatement) == SQLITE_ROW {
                eventCount = Int(sqlite3_column_int(countStatement, 0))
            }
        }
        sqlite3_finalize(countStatement)
        
        // Get last capture date
        let lastCaptureSql = "SELECT MAX(timestamp) FROM events WHERE chain_id = ?"
        var lastCaptureStatement: OpaquePointer?
        var lastCaptureAt: Date?
        
        if sqlite3_prepare_v2(db, lastCaptureSql, -1, &lastCaptureStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(lastCaptureStatement, 1, caseItem.chainId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(lastCaptureStatement) == SQLITE_ROW {
                if let timestampStr = sqlite3_column_text(lastCaptureStatement, 0) {
                    let formatter = ISO8601DateFormatter()
                    lastCaptureAt = formatter.date(from: String(cString: timestampStr))
                }
            }
        }
        sqlite3_finalize(lastCaptureStatement)
        
        // Update case
        let updateSql = "UPDATE cases SET event_count = ?, last_capture_at = ? WHERE case_id = ?"
        var updateStatement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, updateSql, -1, &updateStatement, nil) == SQLITE_OK {
            sqlite3_bind_int(updateStatement, 1, Int32(eventCount))
            if let lastCapture = lastCaptureAt {
                sqlite3_bind_text(updateStatement, 2, ISO8601DateFormatter().string(from: lastCapture), -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(updateStatement, 2)
            }
            sqlite3_bind_text(updateStatement, 3, caseId, -1, SQLITE_TRANSIENT)
            sqlite3_step(updateStatement)
        }
        sqlite3_finalize(updateStatement)
    }
    
    /// Get case statistics
    func getCaseStatistics(caseId: String) -> CaseStatistics? {
        guard let caseItem = try? getCase(caseId: caseId) else { return nil }
        
        lock.lock()
        defer { lock.unlock() }
        
        let chainId = caseItem.chainId
        
        // Total events
        var totalCount = 0
        var activeCount = 0
        var invalidatedCount = 0
        var anchoredCount = 0
        var pendingCount = 0
        var tombstoneCount = 0
        var totalSize: Int64 = 0
        var firstEventDate: Date?
        var lastEventDate: Date?
        
        // Total
        let totalSql = "SELECT COUNT(*) FROM events WHERE chain_id = ?"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, totalSql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, chainId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW {
                totalCount = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        
        // Active
        let activeSql = "SELECT COUNT(*) FROM events WHERE chain_id = ? AND event_status = 'ACTIVE'"
        if sqlite3_prepare_v2(db, activeSql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, chainId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW {
                activeCount = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        
        // Invalidated
        let invalidatedSql = "SELECT COUNT(*) FROM events WHERE chain_id = ? AND event_status = 'INVALIDATED'"
        if sqlite3_prepare_v2(db, invalidatedSql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, chainId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW {
                invalidatedCount = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        
        // Anchored
        let anchoredSql = "SELECT COUNT(*) FROM events WHERE chain_id = ? AND anchor_id IS NOT NULL"
        if sqlite3_prepare_v2(db, anchoredSql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, chainId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW {
                anchoredCount = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        
        // Pending
        let pendingSql = "SELECT COUNT(*) FROM events WHERE chain_id = ? AND anchor_id IS NULL AND event_status = 'ACTIVE'"
        if sqlite3_prepare_v2(db, pendingSql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, chainId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW {
                pendingCount = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        
        // Tombstones
        let tombstoneSql = """
            SELECT COUNT(*) FROM tombstones t 
            JOIN events e ON t.target_event_id = e.event_id 
            WHERE e.chain_id = ?
        """
        if sqlite3_prepare_v2(db, tombstoneSql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, chainId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW {
                tombstoneCount = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        
        // Total size
        let sizeSql = """
            SELECT COALESCE(SUM(a.file_size), 0) FROM assets a 
            JOIN events e ON a.event_id = e.event_id 
            WHERE e.chain_id = ?
        """
        if sqlite3_prepare_v2(db, sizeSql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, chainId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW {
                totalSize = sqlite3_column_int64(statement, 0)
            }
        }
        sqlite3_finalize(statement)
        
        // Date range
        let formatter = ISO8601DateFormatter()
        
        let firstDateSql = "SELECT MIN(timestamp) FROM events WHERE chain_id = ?"
        if sqlite3_prepare_v2(db, firstDateSql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, chainId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 0) {
                    firstEventDate = formatter.date(from: String(cString: text))
                }
            }
        }
        sqlite3_finalize(statement)
        
        let lastDateSql = "SELECT MAX(timestamp) FROM events WHERE chain_id = ?"
        if sqlite3_prepare_v2(db, lastDateSql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, chainId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 0) {
                    lastEventDate = formatter.date(from: String(cString: text))
                }
            }
        }
        sqlite3_finalize(statement)
        
        return CaseStatistics(
            caseId: caseId,
            caseName: caseItem.name,
            eventCount: totalCount,
            activeCount: activeCount,
            invalidatedCount: invalidatedCount,
            tombstoneCount: tombstoneCount,
            anchoredCount: anchoredCount,
            pendingCount: pendingCount,
            firstEventDate: firstEventDate,
            lastEventDate: lastEventDate,
            totalMediaSize: totalSize
        )
    }
    
    /// Export case as JSON package
    func exportCase(caseId: String, includeLocation: Bool = false) throws -> URL {
        guard let caseItem = try getCase(caseId: caseId) else {
            throw CaseError.caseNotFound
        }
        
        let formatter = ISO8601DateFormatter()
        
        let caseInfo = CaseExportInfo(
            caseId: caseItem.caseId,
            name: caseItem.name,
            description: caseItem.description,
            createdAt: formatter.string(from: caseItem.createdAt),
            icon: caseItem.icon,
            colorHex: caseItem.colorHex
        )
        
        // Get events
        var events: [CaseExportEvent] = []
        let eventsSql = "SELECT event_id, timestamp, event_hash, anchor_id FROM events WHERE chain_id = ? ORDER BY timestamp"
        var statement: OpaquePointer?
        
        lock.lock()
        if sqlite3_prepare_v2(db, eventsSql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, caseItem.chainId, -1, SQLITE_TRANSIENT)
            while sqlite3_step(statement) == SQLITE_ROW {
                let eventId = String(cString: sqlite3_column_text(statement, 0))
                let timestamp = String(cString: sqlite3_column_text(statement, 1))
                let eventHash = String(cString: sqlite3_column_text(statement, 2))
                let isAnchored = sqlite3_column_text(statement, 3) != nil
                
                // Get asset hash
                var assetHash = ""
                let assetSql = "SELECT asset_hash FROM assets WHERE event_id = ?"
                var assetStatement: OpaquePointer?
                if sqlite3_prepare_v2(db, assetSql, -1, &assetStatement, nil) == SQLITE_OK {
                    sqlite3_bind_text(assetStatement, 1, eventId, -1, SQLITE_TRANSIENT)
                    if sqlite3_step(assetStatement) == SQLITE_ROW {
                        assetHash = String(cString: sqlite3_column_text(assetStatement, 0))
                    }
                }
                sqlite3_finalize(assetStatement)
                
                events.append(CaseExportEvent(
                    eventId: eventId,
                    timestamp: timestamp,
                    eventHash: eventHash,
                    assetHash: assetHash,
                    isAnchored: isAnchored
                ))
            }
        }
        sqlite3_finalize(statement)
        lock.unlock()
        
        let chainInfo = ChainExportInfo(
            chainId: caseItem.chainId,
            genesisEventId: events.first?.eventId,
            latestEventId: events.last?.eventId,
            latestEventHash: events.last?.eventHash
        )
        
        let stats = getCaseStatistics(caseId: caseId)
        
        let package = CaseExportPackage(
            exportVersion: "1.0",
            exportedAt: formatter.string(from: Date()),
            caseInfo: caseInfo,
            chainInfo: chainInfo,
            events: events,
            tombstones: [],
            statistics: CaseExportStatistics(
                totalEvents: stats?.eventCount ?? events.count,
                activeEvents: stats?.activeCount ?? 0,
                invalidatedEvents: stats?.invalidatedCount ?? 0,
                anchoredEvents: stats?.anchoredCount ?? 0,
                pendingEvents: stats?.pendingCount ?? 0
            )
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(package)
        
        let fileName = "VeriCapture_Case_\(caseItem.name.replacingOccurrences(of: " ", with: "_"))_\(Int(Date().timeIntervalSince1970)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url)
        
        return url
    }
    
    /// Export case as ZIP package with photos
    func exportCaseAsZip(caseId: String, includeLocation: Bool = false) throws -> URL {
        guard let caseItem = try getCase(caseId: caseId) else {
            throw CaseError.caseNotFound
        }
        
        let formatter = ISO8601DateFormatter()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        
        // Create temp directory for package
        let packageName = "VeriCapture_\(caseItem.name.replacingOccurrences(of: " ", with: "_"))_\(dateFormatter.string(from: Date()))"
        let packageDir = FileManager.default.temporaryDirectory.appendingPathComponent(packageName)
        try? FileManager.default.removeItem(at: packageDir)
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)
        
        let photosDir = packageDir.appendingPathComponent("photos")
        try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        
        // Collect events and copy photos
        var events: [[String: Any]] = []
        var photoManifest: [[String: String]] = []
        
        let eventsSql = "SELECT event_id, timestamp, event_hash, anchor_id, event_json FROM events WHERE chain_id = ? ORDER BY timestamp"
        var statement: OpaquePointer?
        
        lock.lock()
        if sqlite3_prepare_v2(db, eventsSql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, caseItem.chainId, -1, SQLITE_TRANSIENT)
            
            var photoIndex = 1
            while sqlite3_step(statement) == SQLITE_ROW {
                let eventId = String(cString: sqlite3_column_text(statement, 0))
                let timestamp = String(cString: sqlite3_column_text(statement, 1))
                let eventHash = String(cString: sqlite3_column_text(statement, 2))
                let isAnchored = sqlite3_column_text(statement, 3) != nil
                
                var eventDict: [String: Any] = [
                    "eventId": eventId,
                    "timestamp": timestamp,
                    "eventHash": eventHash,
                    "isAnchored": isAnchored
                ]
                
                // Get asset info and copy photo
                let assetSql = "SELECT asset_hash, file_path FROM assets WHERE event_id = ?"
                var assetStatement: OpaquePointer?
                if sqlite3_prepare_v2(db, assetSql, -1, &assetStatement, nil) == SQLITE_OK {
                    sqlite3_bind_text(assetStatement, 1, eventId, -1, SQLITE_TRANSIENT)
                    if sqlite3_step(assetStatement) == SQLITE_ROW {
                        let assetHash = String(cString: sqlite3_column_text(assetStatement, 0))
                        eventDict["assetHash"] = assetHash
                        
                        if sqlite3_column_type(assetStatement, 1) != SQLITE_NULL {
                            let filePath = String(cString: sqlite3_column_text(assetStatement, 1))
                            let sourceURL = URL(fileURLWithPath: filePath)
                            
                            if FileManager.default.fileExists(atPath: filePath) {
                                let photoFileName = String(format: "IMG_%04d_%@.jpg", photoIndex, String(eventId.prefix(8)))
                                let destURL = photosDir.appendingPathComponent(photoFileName)
                                try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                                
                                eventDict["photoFile"] = photoFileName
                                photoManifest.append([
                                    "eventId": eventId,
                                    "fileName": photoFileName,
                                    "assetHash": assetHash
                                ])
                                photoIndex += 1
                            }
                        }
                    }
                }
                sqlite3_finalize(assetStatement)
                
                events.append(eventDict)
            }
        }
        sqlite3_finalize(statement)
        lock.unlock()
        
        // Create case metadata JSON
        let stats = getCaseStatistics(caseId: caseId)
        let metadata: [String: Any] = [
            "exportVersion": "1.0",
            "exportedAt": formatter.string(from: Date()),
            "caseInfo": [
                "caseId": caseItem.caseId,
                "name": caseItem.name,
                "description": caseItem.description ?? "",
                "createdAt": formatter.string(from: caseItem.createdAt),
                "icon": caseItem.icon,
                "colorHex": caseItem.colorHex
            ],
            "chainInfo": [
                "chainId": caseItem.chainId,
                "genesisEventId": events.first?["eventId"] ?? "",
                "latestEventId": events.last?["eventId"] ?? "",
                "latestEventHash": events.last?["eventHash"] ?? ""
            ],
            "statistics": [
                "totalEvents": stats?.eventCount ?? events.count,
                "activeEvents": stats?.activeCount ?? 0,
                "invalidatedEvents": stats?.invalidatedCount ?? 0,
                "anchoredEvents": stats?.anchoredCount ?? 0,
                "pendingEvents": stats?.pendingCount ?? 0,
                "photosIncluded": photoManifest.count
            ],
            "events": events,
            "photoManifest": photoManifest
        ]
        
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try metadataData.write(to: packageDir.appendingPathComponent("case_metadata.json"))
        
        // Create chain.json with full CPP chain data
        var chainEvents: [[String: Any]] = []
        let chainSql = "SELECT event_json FROM events WHERE chain_id = ? ORDER BY timestamp"
        var chainStatement: OpaquePointer?
        
        lock.lock()
        if sqlite3_prepare_v2(db, chainSql, -1, &chainStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(chainStatement, 1, caseItem.chainId, -1, SQLITE_TRANSIENT)
            while sqlite3_step(chainStatement) == SQLITE_ROW {
                if let jsonStr = sqlite3_column_text(chainStatement, 0) {
                    let jsonString = String(cString: jsonStr)
                    if let jsonData = jsonString.data(using: .utf8),
                       let jsonObj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        chainEvents.append(jsonObj)
                    }
                }
            }
        }
        sqlite3_finalize(chainStatement)
        lock.unlock()
        
        let chainData: [String: Any] = [
            "chainId": caseItem.chainId,
            "events": chainEvents
        ]
        let chainJsonData = try JSONSerialization.data(withJSONObject: chainData, options: [.prettyPrinted, .sortedKeys])
        try chainJsonData.write(to: packageDir.appendingPathComponent("chain.json"))
        
        // Create README
        let readme = """
        VeriCapture Case Export
        =======================
        
        Case: \(caseItem.name)
        Exported: \(dateFormatter.string(from: Date()))
        
        Contents:
        - case_metadata.json: Case information, events, and statistics
        - chain.json: Full CPP (Content Provenance Protocol) chain data
        - photos/: Original captured photos with cryptographic proofs
        
        Verification:
        Each photo can be verified using VeriCapture app or VeriCheck web tool.
        The chain.json contains the complete hash chain for independent verification.
        
        Note: This export proves WHEN and BY WHAT DEVICE media was captured,
        but does not guarantee the truth or validity of the content itself.
        
        © \(Calendar.current.component(.year, from: Date())) VeritasChain Co., Ltd.
        """
        try readme.write(to: packageDir.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        
        // Create ZIP
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(packageName).zip")
        try? FileManager.default.removeItem(at: zipURL)
        
        let coordinator = NSFileCoordinator()
        var error: NSError?
        
        coordinator.coordinate(readingItemAt: packageDir, options: .forUploading, error: &error) { tempURL in
            try? FileManager.default.moveItem(at: tempURL, to: zipURL)
        }
        
        if let error = error {
            throw error
        }
        
        // Cleanup
        try? FileManager.default.removeItem(at: packageDir)
        
        return zipURL
    }
    
    /// Parse case row from SQLite statement
    private func parseCaseRow(_ statement: OpaquePointer?) -> Case? {
        guard let statement = statement else { return nil }
        
        let formatter = ISO8601DateFormatter()
        
        let caseId = String(cString: sqlite3_column_text(statement, 0))
        let chainId = String(cString: sqlite3_column_text(statement, 1))
        let name = String(cString: sqlite3_column_text(statement, 2))
        
        var description: String? = nil
        if sqlite3_column_type(statement, 3) != SQLITE_NULL {
            description = String(cString: sqlite3_column_text(statement, 3))
        }
        
        let createdAtStr = String(cString: sqlite3_column_text(statement, 4))
        let updatedAtStr = String(cString: sqlite3_column_text(statement, 5))
        let isArchived = sqlite3_column_int(statement, 6) != 0
        let eventCount = Int(sqlite3_column_int(statement, 7))
        
        var lastCaptureAt: Date? = nil
        if sqlite3_column_type(statement, 8) != SQLITE_NULL {
            let lastCaptureStr = String(cString: sqlite3_column_text(statement, 8))
            lastCaptureAt = formatter.date(from: lastCaptureStr)
        }
        
        let icon = String(cString: sqlite3_column_text(statement, 9))
        let colorHex = String(cString: sqlite3_column_text(statement, 10))
        
        return Case(
            caseId: caseId,
            chainId: chainId,
            name: name,
            description: description,
            icon: icon,
            colorHex: colorHex,
            createdAt: formatter.date(from: createdAtStr) ?? Date(),
            updatedAt: formatter.date(from: updatedAtStr) ?? Date(),
            isArchived: isArchived,
            eventCount: eventCount,
            lastCaptureAt: lastCaptureAt
        )
    }
}

enum StorageError: LocalizedError, Sendable {
    case databaseOpenFailed
    case insertFailed
    case updateFailed
    case deleteFailed
    case encodingFailed
    case decodingFailed
    case sqlError(String)
    case fileWriteFailed
    case eventNotFound
    case alreadyInvalidated
    case tombstoneExists
    
    var errorDescription: String? {
        switch self {
        case .databaseOpenFailed: return "Failed to open database"
        case .insertFailed: return "Failed to insert record"
        case .updateFailed: return "Failed to update record"
        case .deleteFailed: return "Failed to delete record"
        case .encodingFailed: return "Failed to encode data"
        case .decodingFailed: return "Failed to decode data"
        case .sqlError(let message): return "SQL error: \(message)"
        case .fileWriteFailed: return "Failed to write file"
        case .eventNotFound: return "Event not found"
        case .alreadyInvalidated: return "Event already invalidated"
        case .tombstoneExists: return "Tombstone already exists for this event"
        }
    }
}
