//
//  MerkleTree.swift
//  VeraSnap
//
//  RFC 6962 Compliant Merkle Tree Implementation
//  Supports root calculation and proof generation for each leaf
//  © 2026 VeritasChain Standards Organization
//

import Foundation
import CryptoKit

/// Merkle Tree implementation with proof generation
/// Follows RFC 6962 (Certificate Transparency) structure
struct MerkleTree {
    
    /// Leaf data with hash and proof
    struct LeafProof: Codable, Sendable {
        let index: Int
        let leafHash: String       // sha256:<hex>
        let proof: [String]        // Array of sibling hashes (sha256:<hex>)
    }
    
    /// Result of Merkle tree construction
    struct TreeResult: Sendable {
        let root: String           // sha256:<hex>
        let treeSize: Int          // Number of leaves
        let leafProofs: [LeafProof]  // Proof for each leaf
    }
    
    // MARK: - Public API
    
    /// Build Merkle tree and generate proofs for all leaves
    /// - Parameter eventHashes: Array of event hashes (sha256:<hex> format)
    /// - Returns: TreeResult containing root and all leaf proofs
    static func build(eventHashes: [String]) -> TreeResult {
        guard !eventHashes.isEmpty else {
            // Empty tree
            return TreeResult(
                root: "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                treeSize: 0,
                leafProofs: []
            )
        }
        
        // Single leaf case - no proof needed
        if eventHashes.count == 1 {
            let leafHash = computeLeafHash(eventHashes[0])
            return TreeResult(
                root: leafHash,
                treeSize: 1,
                leafProofs: [
                    LeafProof(index: 0, leafHash: leafHash, proof: [])
                ]
            )
        }
        
        // Multiple leaves - build full tree with proofs
        return buildTreeWithProofs(eventHashes: eventHashes)
    }
    
    /// Verify a leaf is in the tree using its proof
    /// - Parameters:
    ///   - eventHash: The event hash to verify
    ///   - proof: The Merkle proof (sibling hashes)
    ///   - index: The leaf index
    ///   - treeSize: Total number of leaves
    ///   - expectedRoot: The expected Merkle root
    /// - Returns: true if verification passes
    static func verify(
        eventHash: String,
        proof: [String],
        index: Int,
        treeSize: Int,
        expectedRoot: String
    ) -> Bool {
        // Single leaf case
        if treeSize == 1 && proof.isEmpty && index == 0 {
            let computedRoot = computeLeafHash(eventHash)
            return computedRoot.lowercased() == expectedRoot.lowercased()
        }
        
        // Compute root from proof
        var currentHash = computeLeafHash(eventHash)
        var currentIndex = index
        
        for siblingHash in proof {
            let siblingData = hashToData(siblingHash)
            let currentData = hashToData(currentHash)
            
            // Determine order based on index (even = left, odd = right)
            var combined = Data()
            if currentIndex % 2 == 0 {
                // Current is left sibling
                combined.append(currentData)
                combined.append(siblingData)
            } else {
                // Current is right sibling
                combined.append(siblingData)
                combined.append(currentData)
            }
            
            currentHash = "sha256:" + SHA256.hash(data: combined).hexString
            currentIndex /= 2
        }
        
        return currentHash.lowercased() == expectedRoot.lowercased()
    }
    
    // MARK: - Private Implementation
    
    /// Build tree and collect proofs for all leaves
    private static func buildTreeWithProofs(eventHashes: [String]) -> TreeResult {
        let n = eventHashes.count
        
        // Initialize leaf hashes
        var leafHashes: [String] = eventHashes.map { computeLeafHash($0) }
        
        // Pad to power of 2 if needed (duplicate last element)
        var paddedLeaves = leafHashes
        let nextPowerOf2 = nextPow2(n)
        while paddedLeaves.count < nextPowerOf2 {
            paddedLeaves.append(paddedLeaves.last!)
        }
        
        // Build tree levels (bottom to top)
        var levels: [[String]] = [paddedLeaves]
        var currentLevel = paddedLeaves
        
        while currentLevel.count > 1 {
            var nextLevel: [String] = []
            for i in stride(from: 0, to: currentLevel.count, by: 2) {
                let left = currentLevel[i]
                let right = currentLevel[i + 1]
                let parentHash = computeParentHash(left: left, right: right)
                nextLevel.append(parentHash)
            }
            levels.append(nextLevel)
            currentLevel = nextLevel
        }
        
        let root = currentLevel[0]
        
        // Generate proofs for original leaves only (not padded)
        var leafProofs: [LeafProof] = []
        
        for i in 0..<n {
            let proof = generateProof(leafIndex: i, levels: levels)
            leafProofs.append(LeafProof(
                index: i,
                leafHash: leafHashes[i],
                proof: proof
            ))
        }
        
        return TreeResult(
            root: root,
            treeSize: n,
            leafProofs: leafProofs
        )
    }
    
    /// Generate Merkle proof for a specific leaf
    private static func generateProof(leafIndex: Int, levels: [[String]]) -> [String] {
        var proof: [String] = []
        var index = leafIndex
        
        // Traverse from leaf level to root (excluding root level)
        for level in 0..<(levels.count - 1) {
            let levelNodes = levels[level]
            
            // Find sibling index
            let siblingIndex = (index % 2 == 0) ? index + 1 : index - 1
            
            // Ensure sibling exists
            if siblingIndex < levelNodes.count {
                proof.append(levelNodes[siblingIndex])
            }
            
            // Move to parent index
            index /= 2
        }
        
        return proof
    }
    
    /// Compute leaf hash from event hash
    /// LeafHash = SHA256(EventHash)
    private static func computeLeafHash(_ eventHash: String) -> String {
        let data = hashToData(eventHash)
        let hash = SHA256.hash(data: data)
        return "sha256:" + hash.hexString
    }
    
    /// Compute parent hash from two children
    private static func computeParentHash(left: String, right: String) -> String {
        var combined = Data()
        combined.append(hashToData(left))
        combined.append(hashToData(right))
        let hash = SHA256.hash(data: combined)
        return "sha256:" + hash.hexString
    }
    
    /// Convert hash string to Data
    private static func hashToData(_ hash: String) -> Data {
        let hex = hash.replacingOccurrences(of: "sha256:", with: "")
        return Data(hexString: hex) ?? Data()
    }
    
    /// Find next power of 2
    private static func nextPow2(_ n: Int) -> Int {
        var v = n
        v -= 1
        v |= v >> 1
        v |= v >> 2
        v |= v >> 4
        v |= v >> 8
        v |= v >> 16
        v += 1
        return max(v, 1)
    }
}
