//
//  Localization.swift
//  VeriCapture
//
//  Localization Helper Extensions
//  © 2026 VeritasChain株式会社
//

import Foundation

// MARK: - Localized String Helper

extension String {
    /// Returns a localized string using the key
    var localized: String {
        NSLocalizedString(self, comment: "")
    }
    
    /// Returns a localized string with format arguments
    func localized(_ args: CVarArg...) -> String {
        String(format: NSLocalizedString(self, comment: ""), arguments: args)
    }
}

// MARK: - Localization Keys

enum L10n {
    // App (Global)
    enum App {
        static let tagline = "app.tagline".localized
    }
    
    // Tab Bar
    enum Tab {
        static let capture = "tab.capture".localized
        static let gallery = "tab.gallery".localized
        static let verify = "tab.verify".localized
        static let settings = "tab.settings".localized
    }
    
    // Camera
    enum Camera {
        static let cppOn = "camera.cpp_on".localized
        static let permissionTitle = "camera.permission.title".localized
        static let permissionMessage = "camera.permission.message".localized
        static let permissionButton = "camera.permission.button".localized
        static let toastCaptured = "camera.toast.captured".localized
        static let firstCaptureHint = "camera.first_capture_hint".localized
        static let privacyNote = "camera.privacy_note".localized
        static let firstCaptureLoading = "camera.first_capture_loading".localized
        static let cppProofGeneration = "camera.cpp_proof_generation".localized
        static let authInProgress = "camera.auth_in_progress".localized
        static let keepDeviceStill = "camera.keep_device_still".localized
    }
    
    // Capture Result
    enum Result {
        static let title = "result.title".localized
        static let close = "result.close".localized
        static let generated = "result.generated".localized
        static let anchored = "result.anchored".localized
        static let pending = "result.pending".localized
        static let error = "result.error".localized
        static let proofId = "result.proof_id".localized
        static let filename = "result.filename".localized
        static let filesize = "result.filesize".localized
        static let timestamp = "result.timestamp".localized
        static let hashAlgo = "result.hash_algo".localized
        static let signAlgo = "result.sign_algo".localized
        static let anchorStatus = "result.anchor_status".localized
        static let anchorPending = "result.anchor_pending".localized
        static let anchorComplete = "result.anchor_complete".localized
        static let thirdPartyVerifiable = "result.third_party_verifiable".localized
        static let share = "result.share".localized
        static let copyProofId = "result.copy_proof_id".localized
        static let copyProofUrl = "result.copy_proof_url".localized
    }
    
    // Share
    enum Share {
        static let title = "share.title".localized
        static let cancel = "share.cancel".localized
        static let imageOnly = "share.image_only".localized
        static let imageOnlyDesc = "share.image_only.desc".localized
        static let withProof = "share.with_proof".localized
        static let withProofDesc = "share.with_proof.desc".localized
        static let withQR = "share.with_qr".localized
        static let withQRDesc = "share.with_qr.desc".localized
        static let snsNote = "share.sns_note".localized
        // Additional
        static let internalAboutTitle = "share.internal_about_title".localized
        static let internalAboutDesc = "share.internal_about_desc".localized
        static let privacyDesignTitle = "share.privacy_design_title".localized
        static let privacyDesignDesc = "share.privacy_design_desc".localized
        static let snsWarningTitle = "share.sns_warning_title".localized
        static let snsWarningDesc = "share.sns_warning_desc".localized
        static let recommendedBadge = "share.recommended_badge".localized
        static let ecosystemWarningTitle = "share.ecosystem_warning_title".localized
        static let ecosystemWarningDesc = "share.ecosystem_warning_desc".localized
        static let ecosystemRecommendation = "share.ecosystem_recommendation".localized
        // Location
        static let includeLocation = "share.include_location".localized
        static let includeLocationNote = "share.include_location_note".localized
        static let locationNoData = "share.location_no_data".localized
        // Raw Data Export
        static let rawDataExport = "share.raw_data_export".localized
        static let rawDataExportDesc = "share.raw_data_export_desc".localized
        static let rawDataExportNote = "share.raw_data_export_note".localized
        static let forVerification = "share.for_verification".localized
    }
    
    // QR Preview
    enum QR {
        static let title = "qr.title".localized
        static let position = "qr.position".localized
        static let positionBottomRight = "qr.position.bottom_right".localized
        static let positionBottomLeft = "qr.position.bottom_left".localized
        static let opacity = "qr.opacity".localized
        static let shareThis = "qr.share_this".localized
        static let verifyNote = "qr.verify_note".localized
        static let verifyDesc = "qr.verify_desc".localized
        // Additional
        static let styleTitle = "qr.style_title".localized
        static let styleStandard = "qr.style_standard".localized
        static let styleRounded = "qr.style_rounded".localized
        static let styleBranded = "qr.style_branded".localized
        static let preparingImage = "qr.preparing_image".localized
    }
    
    // Gallery
    enum Gallery {
        static let title = "gallery.title".localized
        static let emptyTitle = "gallery.empty.title".localized
        static let emptyMessage = "gallery.empty.message".localized
        static let statusGenerated = "gallery.status.generated".localized
        static let statusAnchored = "gallery.status.anchored".localized
        static let statusPending = "gallery.status.pending".localized
        static let statusFailed = "gallery.status.failed".localized
        static let statusLegendAnchored = "gallery.status_legend.anchored".localized
        static let statusLegendPending = "gallery.status_legend.pending".localized
        // Date groups
        static let groupPinned = "gallery.group.pinned".localized
        static let groupToday = "gallery.group.today".localized
        static let groupYesterday = "gallery.group.yesterday".localized
        static let groupThisWeek = "gallery.group.this_week".localized
        static let groupThisMonth = "gallery.group.this_month".localized
    }
    
    // Event Detail
    enum Detail {
        static let title = "detail.title".localized
        static let share = "detail.share".localized
        static let delete = "detail.delete".localized
        static let deleteConfirmTitle = "detail.delete.confirm_title".localized
        static let deleteConfirmMessage = "detail.delete.confirm_message".localized
        static let deleteConfirmDelete = "detail.delete.confirm_delete".localized
        static let deleteConfirmCancel = "detail.delete.confirm_cancel".localized
        static let sectionBasic = "detail.section.basic".localized
        static let sectionCrypto = "detail.section.crypto".localized
        static let sectionAnchor = "detail.section.anchor".localized
        static let captureLocation = "detail.capture_location".localized
        static let captureLocationMarker = "detail.capture_location_marker".localized
        static let locationPrivacyNote = "detail.location_privacy_note".localized
        static let proofIdNote = "detail.proof_id_note".localized
        static let signerNote = "detail.signer_note".localized
        static let forensicExport = "detail.forensic_export".localized
        static let preparingProof = "detail.preparing_proof".localized
        // Anchor Info
        static let anchorInfo = "detail.anchor_info".localized
        static let anchorProvider = "detail.anchor_provider".localized
        static let anchorTime = "detail.anchor_time".localized
        static let anchorId = "detail.anchor_id".localized
        // Invalidation
        static func invalidatedAt(_ time: String) -> String {
            String(format: "detail.invalidated_at".localized, time)
        }
        // Human Attestation
        static let humanAttestation = "detail.human_attestation".localized
        // Labels
        static let proofId = "detail.proof_id".localized
        static let assetHash = "detail.asset_hash".localized
        static let eventHash = "detail.event_hash".localized
    }
    
    // Timestamp
    enum Timestamp {
        static let none = "timestamp.none".localized
    }
    
    // Verify (VeriCheck Integration)
    enum Verify {
        static let title = "verify.title".localized
        static let subtitle = "verify.subtitle".localized
        static let scanQR = "verify.scan_qr".localized
        static let scanQRDesc = "verify.scan_qr_desc".localized
        static let selectFile = "verify.select_file".localized
        static let inputJSON = "verify.input_json".localized
        static let inputJSONTitle = "verify.input_json_title".localized
        static let recentVerifications = "verify.recent_verifications".localized
        static let clear = "verify.clear".localized
        static let paste = "verify.paste".localized
        static let verify = "verify.verify".localized
        static let cancel = "verify.cancel".localized
        static let checkItems = "verify.check_items".localized
        static let checkEventHash = "verify.check_event_hash".localized
        static let checkSignature = "verify.check_signature".localized
        static let checkImageHash = "verify.check_image_hash".localized
        static let checkTimestamp = "verify.check_timestamp".localized
        static let qrInstruction = "verify.qr_instruction".localized
        static let resultTitle = "verify.result_title".localized
        static let itemsPassed = "verify.items_passed".localized
        static let proofInfo = "verify.proof_info".localized
        static let proofFile = "verify.proof_file".localized
        static let captureTime = "verify.capture_time".localized
        static let device = "verify.device".localized
        static let generatedBy = "verify.generated_by".localized
        static let tsaTime = "verify.tsa_time".localized
        static let tsaService = "verify.tsa_service".localized
        static let tsaStatus = "verify.tsa_status".localized
        static let tsaPending = "verify.tsa_pending".localized
        static let signerName = "verify.signer_name".localized
        static let flashMode = "verify.flash_mode".localized
        static let errorTitle = "verify.error_title".localized
        static let instructionText = "verify.instruction_text".localized
        // Status
        static let statusVerified = "verify.status.verified".localized
        static let statusSignatureInvalid = "verify.status.signature_invalid".localized
        static let statusHashMismatch = "verify.status.hash_mismatch".localized
        static let statusAnchorPending = "verify.status.anchor_pending".localized
        static let statusAnchorVerified = "verify.status.anchor_verified".localized
        static let statusAssetMismatch = "verify.status.asset_mismatch".localized
        static let statusPending = "verify.status.pending".localized
        static let statusError = "verify.status.error".localized
        // JSON Input
        static let jsonInputTitle = "verify.json_input.title".localized
        static let jsonInputDescription = "verify.json_input.description".localized
        // Result messages
        static let resultAuthenticMessage = "verify.result.authentic_message".localized
        static let resultHashMismatchMessage = "verify.result.hash_mismatch_message".localized
        static let resultAttestationSection = "verify.result.attestation_section".localized
        static let resultAttestationDescription = "verify.result.attestation_description".localized
        static let resultLocationSection = "verify.result.location_section".localized
        static let resultLatitude = "verify.result.latitude".localized
        static let resultLongitude = "verify.result.longitude".localized
        static let resultLocationWarning = "verify.result.location_warning".localized
        static let resultSignatureInvalidMessage = "verify.result.signature_invalid_message".localized
        static let resultAssetMismatchMessage = "verify.result.asset_mismatch_message".localized
        static let resultAnchorPendingMessage = "verify.result.anchor_pending_message".localized
        static let resultPendingMessage = "verify.result.pending_message".localized
        static let resultErrorMessage = "verify.result.error_message".localized
        // Check names
        static let checkJsonParse = "verify.check.json_parse".localized
        static let checkVersion = "verify.check.version".localized
        static let checkEventHashName = "verify.check.event_hash".localized
        static let checkSignatureName = "verify.check.signature".localized
        static let checkImageHashName = "verify.check.image_hash".localized
        // Check steps
        static let checkStep1 = "verify.check.step1".localized
        static let checkStep2 = "verify.check.step2".localized
        static let checkStep3 = "verify.check.step3".localized
        static let checkStep4 = "verify.check.step4".localized
        static let checkStepImage = "verify.check.step_image".localized
        // Check details
        static let checkVersionSupported = "verify.check.version_supported".localized
        static let checkVersionUnsupported = "verify.check.version_unsupported".localized
        static let checkHashMatch = "verify.check.hash_match".localized
        static let checkHashMismatch = "verify.check.hash_mismatch".localized
        static let checkHashFormatOk = "verify.check.hash_format_ok".localized
        static let checkHashFormatInvalid = "verify.check.hash_format_invalid".localized
        static let checkImageNotProvided = "verify.check.image_not_provided".localized
        static let checkEventHashDesc = "verify.check.event_hash_desc".localized
        static let checkEventHashFormatDesc = "verify.check.event_hash_format_desc".localized
        static let checkJsonParseDesc = "verify.check.json_parse_desc".localized
        static let checkVersionDesc = "verify.check.version_desc".localized
        static let checkSignatureDesc = "verify.check.signature_desc".localized
        static let checkImageHashDesc = "verify.check.image_hash_desc".localized
        static let checkSignatureValid = "verify.check.signature_valid".localized
        static let checkSignatureInvalid = "verify.check.signature_invalid".localized
        static let checkImageMatch = "verify.check.image_match".localized
        static let checkImageMismatch = "verify.check.image_mismatch".localized
        static func checkVerificationError(_ error: String) -> String {
            return "verify.check.verification_error".localized(error)
        }
        static let checkStepTsa = "verify.check.step_tsa".localized
        // Merkle
        static let checkMerkle = "verify.check.merkle".localized
        static let checkMerkleDesc = "verify.check.merkle_desc".localized
        static let checkMerkleMatch = "verify.check.merkle_match".localized
        static let checkMerkleMismatch = "verify.check.merkle_mismatch".localized
        // TSA
        static let checkTsa = "verify.check.tsa".localized
        static let checkTsaDesc = "verify.check.tsa_desc".localized
        // Signature presence
        static let checkSignaturePresenceDesc = "verify.check.signature_presence_desc".localized
        static let checkSignaturePresent = "verify.check.signature_present".localized
        static let checkSignatureMissing = "verify.check.signature_missing".localized
        static let checkSignatureNoPublicKey = "verify.check.signature_no_public_key".localized
        // Shareable format
        static func checkShareableFormat(_ version: String) -> String {
            return "verify.check.shareable_format".localized(version)
        }
        static let checkUnknown = "verify.check.unknown".localized
        // Error
        static let errorInvalidFormat = "verify.error.invalid_format".localized
        
        // QR Scan Proof Request (for when QR only contains ID, not full proof)
        static let proofNeededTitle = "verify.proof_needed_title".localized
        static let proofNeededMessage = "verify.proof_needed_message".localized
        static let requestData = "verify.request_data".localized
        static let requestProofLine1 = "verify.request_proof_line1".localized
        static let requestProofLine2 = "verify.request_proof_line2".localized
        static let requestProofFooter = "verify.request_proof_footer".localized
        static let requestProofDisclaimer = "verify.request_proof_disclaimer".localized
        
        // QR Scanner Errors
        static let qrErrorCameraUnavailable = "verify.qr_error.camera_unavailable".localized
        static let qrErrorPermissionDenied = "verify.qr_error.permission_denied".localized
        
        // Image Verification (AssetHash)
        static let imageVerificationTitle = "verify.image_verification_title".localized
        static let imageVerificationDesc = "verify.image_verification_desc".localized
        static let expectedAssetHash = "verify.expected_asset_hash".localized
        static let selectImageToVerify = "verify.select_image_to_verify".localized
        static let selectImageHint = "verify.select_image_hint".localized
        static let selectImageFromFiles = "verify.select_image_from_files".localized
        static let imageSelected = "verify.image_selected".localized
        static let changeImage = "verify.change_image".localized
        static let verifyWithImage = "verify.verify_with_image".localized
        static let verifyWithoutImage = "verify.verify_without_image".localized
        static let skipImageVerification = "verify.skip_image_verification".localized
        static let imageVerificationNote = "verify.image_verification_note".localized
        static let assetHashVerification = "verify.asset_hash_verification".localized
    }
    
    // Settings
    enum Settings {
        static let title = "settings.title".localized
        static let version = "settings.version".localized
        static let aboutTitle = "settings.about.title".localized
        static let aboutDescription = "settings.about.description".localized
        static let timestampTitle = "settings.timestamp.title".localized
        static let timestampPending = "settings.timestamp.pending".localized
        static let timestampLast = "settings.timestamp.last".localized
        static let timestampTrigger = "settings.timestamp.trigger".localized
        static let timestampFooter = "settings.timestamp.footer".localized
        static let timestampFooterPro = "settings.timestamp.footer_pro".localized
        static let timestampOfflineNote = "settings.timestamp.offline_note".localized
        static let tsaProvider = "settings.tsa.provider".localized
        static let tsaConfigure = "settings.tsa.configure".localized
        static let locationTitle = "settings.location.title".localized
        static let locationNote = "settings.location.note".localized
        static let locationStatusTitle = "settings.location.status_title".localized
        static let locationStatusOn = "settings.location.status_on".localized
        static let locationStatusOff = "settings.location.status_off".localized
        static let locationStatusNotDetermined = "settings.location.status_not_determined".localized
        static let locationOpenSettings = "settings.location.open_settings".localized
        static let locationOnDesc = "settings.location.on_desc".localized
        static let locationOffDesc = "settings.location.off_desc".localized
        static let languageTitle = "settings.language.title".localized
        static let languageCurrent = "settings.language.current".localized
        static let languageNote = "settings.language.note".localized
        static let specTitle = "settings.spec.title".localized
        static let specAbout = "settings.spec.about".localized
        static let specCpp = "settings.spec.cpp".localized
        static let specWorldFirst = "settings.spec.world_first".localized
        static let useCasesTitle = "settings.usecases.title".localized
        static let useCasesBrowse = "settings.usecases.browse".localized
        static let useCasesFooter = "settings.usecases.footer".localized
        static let philosophy = "settings.philosophy".localized
        static let philosophyDesc = "settings.philosophy.desc".localized
        static let developer = "settings.developer".localized
        static let developerName = "settings.developer.name".localized
        static let supportMessage = "settings.support_message".localized
        // Plan section
        static let planSection = "settings.plan_section".localized
        static let proActive = "settings.pro_active".localized
        static let manageSubscription = "settings.manage_subscription".localized
        static let freePlan = "settings.free_plan".localized
        static func remainingSlots(_ remaining: Int, _ total: Int) -> String {
            return "settings.remaining_slots".localized(remaining, total)
        }
        static let approachingLimit = "settings.approaching_limit".localized
        static let upgradeToProButton = "settings.upgrade_to_pro".localized
        static let restorePurchases = "settings.restore_purchases".localized
        // Data management section
        static let dataManagement = "settings.data_management".localized
        static let exportAllForensic = "settings.export_all_forensic".localized
        static let exportAllForensicDesc = "settings.export_all_forensic_desc".localized
        static let exportAllForensicFooter = "settings.export_all_forensic_footer".localized
        // Export alert
        static let export = "settings.export".localized
        static let exportingAll = "settings.exporting_all".localized
        // Forensic settings
        static let forensicTitle = "settings.forensic.title".localized
        static let forensicFooter = "settings.forensic.footer".localized
        static let signerNameLabel = "settings.forensic.signer_name_label".localized
        static let signerNamePlaceholder = "settings.forensic.signer_name_placeholder".localized
        static let signerNameHint = "settings.forensic.signer_name_hint".localized
        // Case management
        static let casesTitle = "settings.cases.title".localized
        static let casesFooter = "settings.cases.footer".localized
    }
    
    // Capture View
    enum Capture {
        static let simulatorTitle = "capture.simulator_title".localized
        static let simulatorMessage = "capture.simulator_message".localized
    }
    
    // Attested Capture Mode (旧 Verified Capture Mode)
    enum AttestedCapture {
        static let sectionTitle = "attested_capture.section_title".localized
        static let toggleTitle = "attested_capture.toggle_title".localized
        static let enabled = "attested_capture.enabled".localized
        static let disabled = "attested_capture.disabled".localized
        static let authMethod = "attested_capture.auth_method".localized
        static func description(_ authMethod: String) -> String {
            return "attested_capture.description".localized(authMethod)
        }
        static let disclaimer = "attested_capture.disclaimer".localized
        static let disclaimerFull = "attested_capture.disclaimer_full".localized
        static let notAvailable = "attested_capture.not_available".localized
        static let authFailed = "attested_capture.auth_failed".localized
        static let authCancelled = "attested_capture.auth_cancelled".localized
        static let badge = "attested_capture.badge".localized
        static let badgeTooltip = "attested_capture.badge_tooltip".localized
        static let attestationTitle = "attested_capture.attestation_title".localized
        static let attestationMethod = "attested_capture.attestation_method".localized
        static let attestationTime = "attested_capture.attestation_time".localized
        static let attestationOffset = "attested_capture.attestation_offset".localized
        static let attestationDisclaimer = "attested_capture.attestation_disclaimer".localized
    }
    
    // Export
    enum Export {
        static let forensicTitle = "export.forensic_title".localized
        static let forensicSubtitle = "export.forensic_subtitle".localized
        static let forensicConfirmTitle = "export.forensic_confirm_title".localized
        static let forensicConfirmMessage = "export.forensic_confirm_message".localized
        static let forensicButton = "export.forensic_button".localized
        static let completeTitle = "export.complete_title".localized
        static let authErrorTitle = "export.auth_error_title".localized
        static func authFailedMessage(_ error: String) -> String {
            return "export.auth_failed_message".localized(error)
        }
        
        // Full Chain Export with Tombstones
        static let fullChainTitle = "export.full_chain_title".localized
        static let fullChainDesc = "export.full_chain_desc".localized
        static let includeTombstones = "export.include_tombstones".localized
        static let includeTombstonesDesc = "export.include_tombstones_desc".localized
        static let shareablePackage = "export.shareable_package".localized
        static let shareablePackageDesc = "export.shareable_package_desc".localized
        static let internalPackage = "export.internal_package".localized
        static let internalPackageDesc = "export.internal_package_desc".localized
        static let tombstoneNote = "export.tombstone_note".localized
        static func tombstoneCount(_ count: Int) -> String {
            return "export.tombstone_count".localized(count)
        }
        static let packageGenerated = "export.package_generated".localized
        static func packageIncludes(_ events: Int, _ tombstones: Int) -> String {
            return "export.package_includes".localized(events, tombstones)
        }
    }
    
    // World First Evidence
    enum WorldFirst {
        static let title = "world_first.title".localized
        static let done = "world_first.done".localized
        static let subtitle = "world_first.subtitle".localized
        static let conclusionTitle = "world_first.conclusion_title".localized
        static let conclusionText = "world_first.conclusion_text".localized
        static let conclusionSubtext = "world_first.conclusion_subtext".localized
        static let requirementsTitle = "world_first.requirements_title".localized
        static let req1Title = "world_first.req1_title".localized
        static let req1Desc = "world_first.req1_desc".localized
        static let req2Title = "world_first.req2_title".localized
        static let req2Desc = "world_first.req2_desc".localized
        static let req3Title = "world_first.req3_title".localized
        static let req3Desc = "world_first.req3_desc".localized
        static let req4Title = "world_first.req4_title".localized
        static let req4Desc = "world_first.req4_desc".localized
        static let req5Title = "world_first.req5_title".localized
        static let req5Desc = "world_first.req5_desc".localized
        static let documentId = "world_first.document_id".localized
        static let researchDate = "world_first.research_date".localized
        static let basedOnResearch = "world_first.based_on_research".localized
    }
    
    // Initialization
    enum Init {
        static let title = "init.title".localized
        static let subtitle = "init.subtitle".localized
        static let error = "init.error".localized
    }
    
    // Common
    enum Common {
        static let ok = "common.ok".localized
        static let cancel = "common.cancel".localized
        static let error = "common.error".localized
        static let unknown = "common.unknown".localized
        static let done = "common.done".localized
        static let save = "common.save".localized
        static let delete = "common.delete".localized
        static let edit = "common.edit".localized
    }
    
    // Errors
    enum Error {
        static let title = "error.title".localized
        static let ok = "error.ok".localized
        static let unknown = "error.unknown".localized
    }
    
    // Camera Info Popover
    enum CameraInfo {
        static let title = "camera.info.title".localized
        static let feature1 = "camera.info.feature1".localized
        static let feature2 = "camera.info.feature2".localized
        static let feature3 = "camera.info.feature3".localized
        static let secureEnclave = "camera.info.secure_enclave".localized
        static let disclaimer = "camera.info.disclaimer".localized
    }
    
    // Permission Screen
    enum Permission {
        static let cameraAccess = "permission.camera_access".localized
        static let cameraMessage = "permission.camera_message".localized
        static let allowCamera = "permission.allow_camera".localized
        static let openSettings = "permission.open_settings".localized
    }
    
    // Gallery Context Menu
    enum GalleryContext {
        static let delete = "gallery.context.delete".localized
        static func remaining(_ count: Int) -> String {
            return "gallery.remaining".localized(count)
        }
    }
    
    // Gallery Delete
    enum GalleryDelete {
        static let title = "gallery.delete.title".localized
        static let message = "gallery.delete.message".localized
        static let authError = "gallery.delete.auth_error".localized
    }
    
    // Gallery Pinning
    enum GalleryPin {
        static let pin = "gallery.pin.pin".localized
        static let unpin = "gallery.pin.unpin".localized
    }
    
    // Gallery Search
    enum GallerySearch {
        static let placeholder = "gallery.search.placeholder".localized
        static let noResults = "gallery.search.no_results".localized
        static let clearFilter = "gallery.search.clear_filter".localized
    }
    
    // Gallery Filter
    enum GalleryFilter {
        static let all = "gallery.filter.all".localized
        static let attested = "gallery.filter.attested".localized
        static let anchored = "gallery.filter.anchored".localized
        static let pending = "gallery.filter.pending".localized
    }
    
    // Gallery Selection
    enum GallerySelect {
        static func title(_ count: Int) -> String {
            return "gallery.select.title".localized(count)
        }
        static let selectAll = "gallery.select.select_all".localized
        static let deselectAll = "gallery.select.deselect_all".localized
        static func deleteTitle(_ count: Int) -> String {
            return "gallery.select.delete_title".localized(count)
        }
        static let deleteMessage = "gallery.select.delete_message".localized
    }
    
    // Human Attestation
    enum Attestation {
        static let authMethod = "attestation.auth_method".localized
        static let authTime = "attestation.auth_time".localized
        static let timeOffset = "attestation.time_offset".localized
        static let disclaimer = "attestation.disclaimer".localized
    }
    
    // Export Messages
    enum ExportMessage {
        static let shareSheet = "export.share_sheet".localized
        static let failed = "export.failed".localized
        static let noProofs = "export.no_proofs".localized
        static func error(_ message: String) -> String {
            return "export.error".localized(message)
        }
    }
    
    // Subscription
    enum Subscription {
        static func until(_ date: String) -> String {
            return "subscription.until".localized(date)
        }
        static let restoreTitle = "subscription.restore_title".localized
        static let restoreSuccess = "subscription.restore_success".localized
        static let restoreFailed = "subscription.restore_failed".localized
        static func authFailed(_ error: String) -> String {
            return "subscription.auth_failed".localized(error)
        }
    }
    
    // Paywall
    enum Paywall {
        static let tagline = "paywall.tagline".localized
        static let proBenefitsTitle = "paywall.pro_benefits_title".localized
        static let freeFeaturesTitle = "paywall.free_features_title".localized
        static let featureCapture = "paywall.free_feature.capture".localized
        static let featureProof = "paywall.free_feature.proof".localized
        static let featureQr = "paywall.free_feature.qr".localized
        static let featureJson = "paywall.free_feature.json".localized
        static let selectPlan = "paywall.select_plan".localized
        static let subscriptionInfoTitle = "paywall.subscription_info_title".localized
        static let subscriptionInfoBody = "paywall.subscription_info_body".localized
        static let terms = "paywall.terms".localized
        static let privacy = "paywall.privacy".localized
        // Additional keys for PaywallView
        static let close = "paywall.close".localized
        static let error = "paywall.error".localized
        static let limitReachedTitle = "paywall.limit_reached_title".localized
        static func limitReachedMessage(_ count: Int) -> String {
            return "paywall.limit_reached_message".localized(count)
        }
        static let unlimitedStorage = "paywall.unlimited_storage".localized
        static let freeLimit = "paywall.free_limit".localized
        static let tsaRedundancy = "paywall.tsa_redundancy".localized
        static let tsaRedundancyDesc = "paywall.tsa_redundancy_desc".localized
        static let loadFailed = "paywall.load_failed".localized
        static let reload = "paywall.reload".localized
        static let referencePriceNote = "paywall.reference_price_note".localized
        static let monthlyPlan = "paywall.monthly_plan".localized
        static let yearlyPlan = "paywall.yearly_plan".localized
        static let savePercent = "paywall.save_percent".localized
        static let perMonth = "paywall.per_month".localized
        static let perYear = "paywall.per_year".localized
        static let upgradeButton = "paywall.upgrade_button".localized
        static let restorePurchases = "paywall.restore_purchases".localized
        static let limitReachedCaptureTitle = "paywall.limit_reached_capture_title".localized
        static let limitReachedCaptureMessage = "paywall.limit_reached_capture_message".localized
        static func currentCount(_ current: Int, _ max: Int) -> String {
            return "paywall.current_count".localized(current, max)
        }
        static let proUnlimited = "paywall.pro_unlimited".localized
        static let makeSpace = "paywall.make_space".localized
        static let later = "paywall.later".localized
    }
    
    // Settings Developer
    enum SettingsDeveloper {
        static let lead = "settings.developer_lead".localized
    }
    
    // World First Comparisons
    enum WorldFirstComparison {
        static let title = "world_first.comparison_title".localized
        static let c2paProducts = "world_first.c2pa_products".localized
        static let c2paQuote = "world_first.c2pa_quote".localized
        static let c2paGap = "world_first.c2pa_gap".localized
        static let truepicQuote = "world_first.truepic_quote".localized
        static let truepicGap = "world_first.truepic_gap".localized
        static let numbersQuote = "world_first.numbers_quote".localized
        static let numbersGap = "world_first.numbers_gap".localized
        static let witnessQuote = "world_first.witness_quote".localized
        static let witnessGap = "world_first.witness_gap".localized
        static let starlingQuote = "world_first.starling_quote".localized
        static let starlingGap = "world_first.starling_gap".localized
    }
    
    // World First Findings
    enum WorldFirstFindings {
        static let title = "world_first.findings_title".localized
        static let finding1Title = "world_first.finding1_title".localized
        static let finding1Detail = "world_first.finding1_detail".localized
        static let finding2Title = "world_first.finding2_title".localized
        static let finding2Detail = "world_first.finding2_detail".localized
        static let finding3Title = "world_first.finding3_title".localized
        static let finding3Detail = "world_first.finding3_detail".localized
        static let finding4Title = "world_first.finding4_title".localized
        static let finding4Detail = "world_first.finding4_detail".localized
    }
    
    // World First Technical Notes
    enum WorldFirstTech {
        static let title = "world_first.tech_notes_title".localized
        static let whoEqualsDevice = "world_first.who_equals_device".localized
        static let whoExplanation = "world_first.who_explanation".localized
        static let deviceProof = "world_first.device_proof".localized
        static let futureUpdates = "world_first.future_updates".localized
        static let futureExplanation = "world_first.future_explanation".localized
    }
    
    // World First References
    enum WorldFirstRef {
        static let title = "world_first.references_title".localized
        static let githubReport = "world_first.github_report".localized
        static let capSpec = "world_first.cap_spec".localized
    }
    
    // World First Conclusion
    enum WorldFirstConclusion {
        static let title = "world_first.conclusion_title".localized
        static let text = "world_first.conclusion_text".localized
        static let detail = "world_first.conclusion_detail".localized
    }
    
    // World First Requirements
    enum WorldFirstReq {
        static let title = "world_first.requirements_title".localized
        static let req1Title = "world_first.req1_title".localized
        static let req1Desc = "world_first.req1_desc".localized
        static let req2Title = "world_first.req2_title".localized
        static let req2Desc = "world_first.req2_desc".localized
        static let req3Title = "world_first.req3_title".localized
        static let req3Desc = "world_first.req3_desc".localized
        static let req4Title = "world_first.req4_title".localized
        static let req4Desc = "world_first.req4_desc".localized
        static let req5Title = "world_first.req5_title".localized
        static let req5Desc = "world_first.req5_desc".localized
    }
    
    // World First Footer
    enum WorldFirstFooter {
        static let docId = "world_first.doc_id".localized
        static let researchDate = "world_first.research_date".localized
        static let researchNote = "world_first.research_note".localized
        static let navTitle = "world_first.nav_title".localized
        static let done = "world_first.done".localized
    }
    
    // Pro Subscription Display
    enum ProDisplay {
        static func remaining(_ count: Int) -> String {
            return "pro.remaining_format".localized(count)
        }
        static func until(_ date: String) -> String {
            return "pro.until_format".localized(date)
        }
    }
    
    // Disclaimer & Important Notices
    enum Disclaimer {
        static let title = "disclaimer.title".localized
        static let contentNotGuaranteed = "disclaimer.content_not_guaranteed".localized
        static let recordsOperationOnly = "disclaimer.records_operation_only".localized
        static let requiresVerification = "disclaimer.requires_verification".localized
        static let notIdentityProof = "disclaimer.not_identity_proof".localized
        static let shareNotice = "disclaimer.share_notice".localized
        static let verificationNotice = "disclaimer.verification_notice".localized
    }
    
    // About App (Revised)
    enum About {
        static let toolDefinition = "about.tool_definition".localized
        static let whatItRecords = "about.what_it_records".localized
        static let whatItDoesNot = "about.what_it_does_not".localized
        static let intendedUse = "about.intended_use".localized
    }
    
    // Onboarding
    enum Onboarding {
        static let title1 = "onboarding.title1".localized
        static let desc1 = "onboarding.desc1".localized
        static let title2 = "onboarding.title2".localized
        static let desc2 = "onboarding.desc2".localized
        static let title3 = "onboarding.title3".localized
        static let desc3 = "onboarding.desc3".localized
        static let title4 = "onboarding.title4".localized
        static let desc4 = "onboarding.desc4".localized
        static let next = "onboarding.next".localized
        static let start = "onboarding.start".localized
        static let skip = "onboarding.skip".localized
    }
    
    // MARK: - CPP Additional Spec Localization
    
    // Media Status
    enum MediaStatus {
        static let present = "media_status.present".localized
        static let purged = "media_status.purged".localized
        static let corrupted = "media_status.corrupted".localized
        static let migrated = "media_status.migrated".localized
    }
    
    // Event Status
    enum EventStatus {
        static let active = "event_status.active".localized
        static let invalidated = "event_status.invalidated".localized
        static let superseded = "event_status.superseded".localized
    }
    
    // Anchor Status Display
    enum AnchorStatusDisplay {
        static let pending = "anchor_status.pending".localized
        static let anchored = "anchor_status.anchored".localized
        static let failed = "anchor_status.failed".localized
        static let skipped = "anchor_status.skipped".localized
        static let pendingDescription = "anchor_status.pending_description".localized
        static let anchoredDescription = "anchor_status.anchored_description".localized
        static let failedDescription = "anchor_status.failed_description".localized
        static let triggerNow = "anchor_status.trigger_now".localized
    }
    
    // Invalidation Reason
    enum InvalidationReason {
        static let privacy = "invalidation_reason.privacy".localized
        static let accidental = "invalidation_reason.accidental".localized
        static let inappropriate = "invalidation_reason.inappropriate".localized
        static let courtOrder = "invalidation_reason.court_order".localized
        static let gdpr = "invalidation_reason.gdpr".localized
        static let duplicate = "invalidation_reason.duplicate".localized
        static let integrity = "invalidation_reason.integrity".localized
    }
    
    // Delete / Purge / Invalidate
    enum Delete {
        static let sheetTitle = "delete.sheet_title".localized
        static let mediaTitle = "delete.media_title".localized
        static let mediaDescription = "delete.media_description".localized
        static let mediaConfirm = "delete.media_confirm".localized
        static let mediaConfirmMessage = "delete.media_confirm_message".localized
        static let mediaButton = "delete.media_button".localized
        static let mediaAlreadyDeleted = "delete.media_already_deleted".localized
        static let mediaDeletedBadge = "delete.media_deleted_badge".localized
        
        static let invalidateTitle = "delete.invalidate_title".localized
        static let invalidateDescription = "delete.invalidate_description".localized
        static let invalidateConfirm = "delete.invalidate_confirm".localized
        static let invalidateConfirmMessage = "delete.invalidate_confirm_message".localized
        static let invalidateButton = "delete.invalidate_button".localized
        static let invalidateSelectReason = "delete.invalidate_select_reason".localized
        
        static let nothingDeleted = "delete.nothing_deleted".localized
        static let recordRemains = "delete.record_remains".localized
        
        // 統合削除用
        static let confirmTitle = "delete.confirm_title".localized
        static let confirmMessage = "delete.confirm_message".localized
        static let confirmButton = "delete.confirm_button".localized
        
        // Error messages
        static let errorTargetNotFound = "delete.error_target_not_found".localized
        static let errorAlreadyInvalidated = "delete.error_already_invalidated".localized
        static let errorEventNotActive = "delete.error_event_not_active".localized
        static let errorSignatureFailed = "delete.error_signature_failed".localized
        static let errorStorageFailed = "delete.error_storage_failed".localized
        static func errorGeneric(_ detail: String) -> String {
            String(format: "delete.error_generic".localized, detail)
        }
        static func errorAuthFailed(_ error: String) -> String {
            String(format: "delete.error_auth_failed".localized, error)
        }
    }
    
    // Forensic Export Warnings
    enum ForensicWarning {
        static let pendingTitle = "forensic_warning.pending_title".localized
        static let pendingMessage = "forensic_warning.pending_message".localized
        static let anchorAll = "forensic_warning.anchor_all".localized
        static let exportAnyway = "forensic_warning.export_anyway".localized
        static let whatIsAnchor = "forensic_warning.what_is_anchor".localized
        static let anchorExplanation = "forensic_warning.anchor_explanation".localized
    }
    
    // Gallery Status Badges
    enum GalleryStatus {
        static let anchored = "gallery_status.anchored".localized
        static let pending = "gallery_status.pending".localized
        static let failed = "gallery_status.failed".localized
        static let invalidated = "gallery_status.invalidated".localized
        static let mediaPurged = "gallery_status.media_purged".localized
    }
    
    // Chain Integrity Verification
    enum Chain {
        static let title = "chain.title".localized
        static let statisticsTitle = "chain.statistics_title".localized
        static let verificationTitle = "chain.verification_title".localized
        static let verificationFooter = "chain.verification_footer".localized
        static let runVerification = "chain.run_verification".localized
        static let errorDetailsTitle = "chain.error_details_title".localized
        static let howItWorks = "chain.how_it_works".localized
        
        // Statistics
        static let totalEvents = "chain.total_events".localized
        static let activeEvents = "chain.active_events".localized
        static let invalidatedEvents = "chain.invalidated_events".localized
        static let tombstones = "chain.tombstones".localized
        static let anchored = "chain.anchored".localized
        static let pendingAnchor = "chain.pending_anchor".localized
        static let dateRange = "chain.date_range".localized
        
        // Verification Results
        static let verificationPassed = "chain.verification_passed".localized
        static let verificationPassedWithWarnings = "chain.verification_passed_with_warnings".localized
        static let verificationFailed = "chain.verification_failed".localized
        static func checkedFormat(_ events: Int, _ tombstones: Int) -> String {
            return "chain.checked_format".localized(events, tombstones)
        }
        static func verifiedAt(_ time: String) -> String {
            return "chain.verified_at".localized(time)
        }
        static func errorsFound(_ count: Int) -> String {
            return "chain.errors_found".localized(count)
        }
        static func warningsFound(_ count: Int) -> String {
            return "chain.warnings_found".localized(count)
        }
        
        // Error Types
        static let errorPrevHash = "chain.error_prev_hash".localized
        static let errorEventHash = "chain.error_event_hash".localized
        static let errorSignature = "chain.error_signature".localized
        static let errorTombstoneTarget = "chain.error_tombstone_target".localized
        static let errorOrphanedTombstone = "chain.error_orphaned_tombstone".localized
        static let errorTimestamp = "chain.error_timestamp".localized
        static let errorDeletedGap = "chain.error_deleted_gap".localized
        
        // Error details
        static let warningBadge = "chain.warning_badge".localized
        static func eventLabel(_ id: String) -> String {
            String(format: "chain.event_label".localized, id)
        }
        static let deletedEventGapMessage = "chain.deleted_event_gap_message".localized
        static func expectedLabel(_ value: String) -> String {
            String(format: "chain.expected_label".localized, value)
        }
        static func actualLabel(_ value: String) -> String {
            String(format: "chain.actual_label".localized, value)
        }
        
        // Explanations
        static let explainPrevHash = "chain.explain_prev_hash".localized
        static let explainPrevHashDesc = "chain.explain_prev_hash_desc".localized
        static let explainEventHash = "chain.explain_event_hash".localized
        static let explainEventHashDesc = "chain.explain_event_hash_desc".localized
        static let explainTombstone = "chain.explain_tombstone".localized
        static let explainTombstoneDesc = "chain.explain_tombstone_desc".localized
        
        // Reset Chain
        static let dangerZone = "chain.danger_zone".localized
        static let resetChain = "chain.reset_chain".localized
        static let resetChainFooter = "chain.reset_chain_footer".localized
        static let resetConfirmTitle = "chain.reset_confirm_title".localized
        static let resetConfirmMessage = "chain.reset_confirm_message".localized
        static let resetConfirmButton = "chain.reset_confirm_button".localized
        static let authError = "chain.auth_error".localized
        static func authFailed(_ error: String) -> String {
            return "chain.auth_failed".localized(error)
        }
        
        // Statistics Notes
        static let statsNote = "chain.stats_note".localized
        static let activeNote = "chain.active_note".localized
        static let invalidatedNote = "chain.invalidated_note".localized
    }
    
    // MARK: - TSA Redundancy (v36)
    
    enum TSA {
        // Provider List
        static let providersTitle = "tsa.providers.title".localized
        static let addCustomProvider = "tsa.add.custom".localized
        static let providerCount = "tsa.provider_count".localized
        
        // Service Levels
        static let production = "tsa.level.production".localized
        static let bestEffort = "tsa.level.bestEffort".localized
        static let demo = "tsa.level.demo".localized
        
        // Warnings
        static func intervalWarning(_ seconds: Int) -> String {
            return "tsa.warning.interval".localized(seconds)
        }
        static func dailyLimitWarning(_ limit: Int) -> String {
            return "tsa.warning.dailyLimit".localized(limit)
        }
        static func monthlyLimitWarning(_ limit: Int) -> String {
            return "tsa.warning.monthlyLimit".localized(limit)
        }
        static let commercialProhibited = "tsa.warning.commercialProhibited".localized
        static let noSLA = "tsa.warning.noSLA".localized
        
        // Documentation
        static let termsOfService = "tsa.tos".localized
        static let cps = "tsa.cps".localized
        
        // Settings
        static let sectionHeader = "tsa.section.header".localized
        static let sectionFooter = "tsa.section.footer".localized
        static let primaryProvider = "tsa.primary_provider".localized
        static let enableRedundancy = "tsa.settings.enableRedundancy".localized
        static let enableRedundancyDesc = "tsa.settings.enableRedundancyDesc".localized
        static let redundancyProOnly = "tsa.settings.proOnly".localized
        static let lastUsedProvider = "tsa.last_used_provider".localized
        
        // Status
        static let statusConnected = "tsa.status.connected".localized
        static let statusDisabled = "tsa.status.disabled".localized
        static let statusRateLimited = "tsa.status.rateLimited".localized
        
        // Regions
        static let regionEU = "tsa.region.eu".localized
        static let regionUS = "tsa.region.us".localized
        static let regionGlobal = "tsa.region.global".localized
        static let regionAPAC = "tsa.region.apac".localized
        
        // eIDAS
        static let eidasQualified = "tsa.eidas.qualified".localized
    }
    
    // MARK: - Case Management (v40)
    
    enum Case {
        // List View
        static let title = "case.title".localized
        static let createNew = "case.create_new".localized
        static let emptyTitle = "case.empty_title".localized
        static let emptyMessage = "case.empty_message".localized
        static let current = "case.current".localized
        static let other = "case.other".localized
        static let archived = "case.archived".localized
        static let showArchived = "case.show_archived".localized
        
        // Form Fields
        static let name = "case.name".localized
        static let namePlaceholder = "case.name_placeholder".localized
        static let description = "case.description".localized
        static let descriptionPlaceholder = "case.description_placeholder".localized
        static let icon = "case.icon".localized
        static let color = "case.color".localized
        
        // Actions
        static let select = "case.select".localized
        static let edit = "case.edit".localized
        static let archive = "case.archive".localized
        static let unarchive = "case.unarchive".localized
        static let delete = "case.delete".localized
        static let export = "case.export".localized
        static let createTitle = "case.create_title".localized
        static let editTitle = "case.edit_title".localized
        static let save = "case.save".localized
        static let create = "case.create".localized
        static let tapToChange = "case.tap_to_change".localized
        
        // Delete Confirmation
        static let deleteConfirmTitle = "case.delete_confirm_title".localized
        static let deleteConfirmMessage = "case.delete_confirm_message".localized
        static let deleteHasEvents = "case.delete_has_events".localized
        
        // Statistics
        static let statsTitle = "case.stats_title".localized
        static let statsTotal = "case.stats_total".localized
        static let statsActive = "case.stats_active".localized
        static let statsInvalidated = "case.stats_invalidated".localized
        static let statsAnchored = "case.stats_anchored".localized
        static let statsPending = "case.stats_pending".localized
        static let statsDateRange = "case.stats_date_range".localized
        static let statsSize = "case.stats_size".localized
        
        // Section Headers
        static let sectionInfo = "case.section_info".localized
        static let sectionEvents = "case.section_events".localized
        static let sectionTechnical = "case.section_technical".localized
        static let noEvents = "case.no_events".localized
        
        // Photo count
        static func photoCount(_ count: Int) -> String {
            String(format: count == 1 ? "case.photo_singular".localized : "case.photo_plural".localized, count)
        }
        static func lastCapture(_ date: String) -> String {
            String(format: "case.last_capture".localized, date)
        }
        
        // Export
        static let exportTitle = "case.export_title".localized
        static let exportSuccess = "case.export_success".localized
        static let exportIncludeLocation = "case.export_include_location".localized
        static let exportMetadataOnly = "case.export_metadata_only".localized
        static let exportFullPackage = "case.export_full_package".localized
        static let exportMessage = "case.export_message".localized
        
        // Quick Capture
        static let quickCapture = "case.quick_capture".localized
        static let selectorTitle = "case.selector_title".localized
        
        // Default Case
        static let defaultName = "case.default_name".localized
    }
}
