import Foundation

public enum CaptureFailure: Error, Codable, Sendable, Equatable, LocalizedError {
    case permissionDenied
    case permissionRevoked
    case microphonePermissionDenied
    case microphoneUnavailable
    case microphoneCaptureFailed
    case outputDeviceUnavailable
    case unsupportedLanguage(SupportedLanguage)
    case speechLanguagePackUnavailable(SupportedLanguage)
    case translationLanguagePackUnavailable
    case automaticModelMissing
    case unsupportedDetectedLanguage
    case silentInput
    case inferenceOverload
    case modelLoadFailed
    case audioSystem(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: "시스템 오디오 권한이 거부되었습니다."
        case .permissionRevoked: "시스템 오디오 권한이 철회되었습니다."
        case .microphonePermissionDenied: "마이크 권한이 거부되었거나 철회되었습니다."
        case .microphoneUnavailable: "사용 가능한 마이크가 없습니다."
        case .microphoneCaptureFailed: "마이크 캡처에 실패했습니다."
        case .outputDeviceUnavailable: "사용 가능한 출력 장치가 없습니다."
        case .unsupportedLanguage(let language): "지원되지 않는 언어입니다: \(language.displayName)"
        case .speechLanguagePackUnavailable(let language): "받아쓰기 언어팩을 준비할 수 없습니다: \(language.displayName)"
        case .translationLanguagePackUnavailable: "번역 언어팩이 설치되지 않았습니다."
        case .automaticModelMissing: "자동 언어 감지용 MLX 모델이 설치되지 않았습니다."
        case .unsupportedDetectedLanguage: "지원 범위 밖의 언어가 감지되었습니다."
        case .silentInput: "입력 오디오가 무음입니다."
        case .inferenceOverload: "받아쓰기 처리가 실시간 속도를 따라가지 못하고 있습니다."
        case .modelLoadFailed: "선택한 로컬 모델을 불러오지 못했습니다."
        case .audioSystem(let reason): "오디오 시스템 오류: \(reason)"
        }
    }
}

public enum CaptureState: Sendable, Equatable {
    case idle
    case requestingPermission
    case preparingModels
    case running
    case stopping
    case failed(CaptureFailure)
}

public enum CaptureTransitionError: Error, Sendable, Equatable {
    case invalid(from: CaptureState, to: CaptureState)
}

public actor CaptureStateMachine {
    public private(set) var state: CaptureState = .idle

    public init() {}

    @discardableResult
    public func transition(to newState: CaptureState) throws -> CaptureState {
        guard Self.isAllowed(from: state, to: newState) else {
            throw CaptureTransitionError.invalid(from: state, to: newState)
        }
        state = newState
        return state
    }

    private static func isAllowed(from: CaptureState, to: CaptureState) -> Bool {
        switch (from, to) {
        case (.idle, .requestingPermission),
             (.idle, .failed),
             (.requestingPermission, .preparingModels),
             (.requestingPermission, .failed),
             (.preparingModels, .running),
             (.preparingModels, .failed),
             (.running, .stopping),
             (.running, .failed),
             (.stopping, .idle),
             (.stopping, .failed),
             (.failed, .idle):
            true
        default:
            false
        }
    }
}

public actor CaptureRecoveryCoordinator {
    private var wasRunningBeforeSleep = false

    public init() {}

    public func prepareForSleep(state: CaptureState) -> Bool {
        wasRunningBeforeSleep = state == .running
        return wasRunningBeforeSleep
    }

    public func shouldRestartAfterWake(permissionAvailable: Bool, outputDeviceAvailable: Bool) -> Bool {
        defer { wasRunningBeforeSleep = false }
        return wasRunningBeforeSleep && permissionAvailable && outputDeviceAvailable
    }

    public func shouldReconfigureForDeviceChange(state: CaptureState) -> Bool {
        state == .running
    }
}

public enum MemoryPressureLevel: Sendable, Equatable {
    case warning
    case critical
}

public enum MemoryPressureRecoveryAction: Sendable, Equatable {
    case keepActiveModels
    case releaseUnusedModels
    case fallbackMLXTranslation
}

public enum MemoryPressureRecoveryPolicy {
    public static func action(
        level: MemoryPressureLevel,
        captureIsActive: Bool,
        mlxTranslationIsLoaded: Bool
    ) -> MemoryPressureRecoveryAction {
        if !captureIsActive {
            return .releaseUnusedModels
        }
        if level == .critical, mlxTranslationIsLoaded {
            return .fallbackMLXTranslation
        }
        return .keepActiveModels
    }
}
