# VeriCapture

iOS cryptographic evidence camera app implementing Content Provenance Protocol (CPP). Captures photos and videos with RFC 3161 timestamps, Merkle tree integrity logging, and biometric authentication.

![Platform](https://img.shields.io/badge/platform-iOS%2017.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-Proprietary-red)

## Overview

VeriCapture is a world-first consumer application that cryptographically binds media capture to verified human presence while maintaining privacy through local processing. It provides tamper-evident digital evidence for legal documentation, real estate verification, construction progress tracking, and audit compliance.

### Core Principle

> **"Provenance ≠ Truth"**
> 
> VeriCapture proves *when* and *by what device* media was captured, but does not guarantee the truth or validity of the content itself.

## Features

### Cryptographic Evidence
- **RFC 3161 TSA Anchoring** - External timestamp verification from trusted authorities
- **ES256 Digital Signatures** - ECDSA signatures using device-bound keys
- **SHA-256 Hash Chains** - Merkle tree integrity logging for tamper detection
- **Biometric Authentication** - Face ID / Touch ID binding at capture time

### Case Management
- Organize captures by project or site
- Independent hash chains per case (CPP compliant)
- Export options: JSON metadata or full ZIP with photos
- Archive and restore functionality

### Verification
- **VeriCheck** - Built-in verification scanner
- **QR Code Sharing** - Share cryptographic proofs instantly
- **Chain Integrity View** - Visualize and audit hash chains

### Privacy by Design
- All processing done locally on device
- No cloud upload required
- "Delete the data, but never delete the truth" - audit trails preserved

## Technical Stack

| Component | Technology |
|-----------|------------|
| Platform | iOS 17.0+ |
| Language | Swift 5.9 |
| UI Framework | SwiftUI |
| Cryptography | CryptoKit (ES256, SHA-256) |
| Camera | AVFoundation |
| Database | SQLite |
| TSA | RFC 3161 compliant services |

## Architecture

```
VeriCapture/
├── Sources/
│   ├── App/                 # App entry point
│   ├── Models/              # Data models (CPPEvent, Case, etc.)
│   ├── Views/               # SwiftUI views
│   ├── Services/            # Business logic
│   │   ├── CameraService    # AVFoundation camera handling
│   │   ├── CryptoService    # Cryptographic operations
│   │   ├── CaseService      # Case management
│   │   └── AnchorService    # TSA anchoring
│   ├── Storage/             # SQLite persistence
│   ├── Crypto/              # Cryptographic utilities
│   ├── Verification/        # VeriCheck implementation
│   └── Utils/               # Localization, helpers
└── Resources/
    ├── Assets.xcassets/     # App icons, colors
    └── *.lproj/             # Localized strings (10 languages)
```

## Specifications

VeriCapture implements the following specifications:

| Specification | Version | Description |
|--------------|---------|-------------|
| [CPP](https://github.com/veritaschain/cpp-spec) | 1.2 | Content Provenance Protocol |
| [VCP](https://github.com/veritaschain/vcp-spec) | 1.1 | VeriCapture Protocol |
| [VAP Framework](https://github.com/veritaschain/vap-spec) | 1.2 | Verifiable AI Provenance Framework |

## Localization

VeriCapture supports 10 languages:

| Language | Code |
|----------|------|
| English | en |
| Japanese | ja |
| Simplified Chinese | zh-Hans |
| Traditional Chinese | zh-Hant |
| Korean | ko |
| German | de |
| French | fr |
| Spanish | es |
| Portuguese | pt |
| Arabic | ar |

## Requirements

- iOS 17.0 or later
- iPhone with Face ID or Touch ID
- Camera access permission
- Internet connection (for TSA anchoring)

## Installation

VeriCapture is available on the [App Store](https://apps.apple.com/app/vericapture).

### For Development

1. Clone the repository
```bash
git clone https://github.com/veritaschain/vericapture.git
cd vericapture
```

2. Open in Xcode
```bash
open VeriCapture.xcodeproj
```

3. Configure signing
   - Set your development team in Signing & Capabilities
   - Update bundle identifier if needed

4. Build and run on a physical device (camera features require real hardware)

## Subscription Plans

| Feature | Free | Pro |
|---------|------|-----|
| Evidence captures | 50 total | Unlimited |
| TSA providers | 1 | 3 (redundant) |
| Case management | ✓ | ✓ |
| VeriCheck verification | ✓ | ✓ |
| Export (JSON) | ✓ | ✓ |
| Export (ZIP with photos) | ✓ | ✓ |
| Priority support | - | ✓ |

## Security

### Threat Model

VeriCapture protects against:
- Post-capture tampering
- Timestamp falsification
- Device spoofing
- Chain manipulation

VeriCapture does NOT protect against:
- Pre-capture staging
- Content authenticity
- Physical world verification

### Cryptographic Details

- **Signing Algorithm**: ES256 (ECDSA with P-256 and SHA-256)
- **Hash Algorithm**: SHA-256
- **Key Storage**: Secure Enclave
- **TSA Protocol**: RFC 3161

## Contributing

This is a proprietary project. For partnership inquiries, contact us at:
- Email: developers@veritaschain.org

## License

Copyright © 2026 VeritasChain Co., Ltd. All rights reserved.

This software is proprietary and confidential. Unauthorized copying, modification, distribution, or use of this software, via any medium, is strictly prohibited.

See [LICENSE](./LICENSE) for details.

## Related Projects

- [VeriCapture Web](https://veritaschain.org/vap/cpp/vericapture/) - Online verification tool
- [VAP Framework](https://github.com/veritaschain/vap-spec) - Verifiable AI Provenance specifications

## Contact

**VeritasChain Co., Ltd.**

- Website: https://veritaschain.org
- Email: info@veritaschain.org
- Developer Contact: developers@veritaschain.org

---

<p align="center">
  <i>"Provenance ≠ Truth"</i><br>
  Built with 🔐 by VeritasChain
</p>
