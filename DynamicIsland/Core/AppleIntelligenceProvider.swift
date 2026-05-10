//
//  AppleIntelligenceProvider.swift
//  DynamicIsland
//
//  Thin wrapper around Apple's on-device FoundationModels framework
//  (Apple Intelligence). Runs entirely locally on the user's Mac, no
//  network, no API key, no per-token cost.
//
//  Requires macOS 26+ on Apple Silicon with Apple Intelligence enabled.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// User-visible availability of Apple Intelligence on this Mac.
enum AIAvailability: Equatable {
    case available
    case osTooOld           // user is on macOS 25 or earlier
    case appleIntelligenceNotEnabled
    case modelNotReady      // still downloading on first use
    case unsupportedDevice  // Intel Mac, etc.
    case unknown(String)

    var headline: String {
        switch self {
        case .available: return "Apple Intelligence is ready"
        case .osTooOld: return "Requires macOS 26 (Tahoe) or later"
        case .appleIntelligenceNotEnabled: return "Apple Intelligence is not enabled"
        case .modelNotReady: return "Apple Intelligence model is still downloading"
        case .unsupportedDevice: return "This Mac doesn't support Apple Intelligence"
        case .unknown(let msg): return "Apple Intelligence unavailable: \(msg)"
        }
    }

    var hint: String {
        switch self {
        case .available: return "All processing happens on this Mac. Free, private, offline."
        case .osTooOld: return "Update macOS in System Settings → General → Software Update."
        case .appleIntelligenceNotEnabled: return "Turn it on in System Settings → Apple Intelligence & Siri."
        case .modelNotReady: return "Open System Settings → Apple Intelligence and wait for the download to finish, then try again."
        case .unsupportedDevice: return "Apple Intelligence requires an Apple Silicon Mac (M1 or later)."
        case .unknown: return "Try again in a moment."
        }
    }
}

/// What the user wants the model to do with a piece of text.
enum AIAction: String, CaseIterable, Identifiable {
    case summarize
    case fixGrammar
    case translateToEnglish
    case translateToHindi
    case explain
    case makeProfessional
    case makeFriendly
    case extractKeyPoints

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summarize: return "Summarize"
        case .fixGrammar: return "Fix Grammar & Spelling"
        case .translateToEnglish: return "Translate to English"
        case .translateToHindi: return "Translate to Hindi"
        case .explain: return "Explain Like I'm 5"
        case .makeProfessional: return "Make it Professional"
        case .makeFriendly: return "Make it Friendly"
        case .extractKeyPoints: return "Extract Key Points"
        }
    }

    var symbolName: String {
        switch self {
        case .summarize: return "text.append"
        case .fixGrammar: return "checkmark.seal"
        case .translateToEnglish: return "character.bubble"
        case .translateToHindi: return "character.bubble.fill"
        case .explain: return "lightbulb"
        case .makeProfessional: return "briefcase"
        case .makeFriendly: return "face.smiling"
        case .extractKeyPoints: return "list.bullet.rectangle"
        }
    }

    /// System instructions that prime the model for this action.
    var instructions: String {
        switch self {
        case .summarize:
            return "You are a concise summarizer. Given a piece of text, produce a short summary in 2-4 sentences. Preserve the original language."
        case .fixGrammar:
            return "You are a careful editor. Fix grammar, spelling and punctuation in the user's text. Preserve meaning, tone, and language. Output only the corrected text — no preamble, no explanation."
        case .translateToEnglish:
            return "You are a faithful translator. Translate the user's text to natural English. Output only the translation."
        case .translateToHindi:
            return "You are a faithful translator. Translate the user's text to natural Hindi (हिन्दी). Output only the translation."
        case .explain:
            return "You explain things in plain, simple language a smart 10-year-old can follow. Use short sentences and concrete examples. Avoid jargon."
        case .makeProfessional:
            return "You are a writing assistant. Rewrite the user's text in a clear, professional tone suitable for business email. Keep meaning and key facts intact. Output only the rewritten text."
        case .makeFriendly:
            return "You are a writing assistant. Rewrite the user's text in a warm, friendly, conversational tone. Keep meaning intact. Output only the rewritten text."
        case .extractKeyPoints:
            return "Extract the most important points from the user's text as a clean Markdown bullet list. 3-7 bullets, each one short."
        }
    }
}

/// Errors surfaced to the UI from the provider.
enum AIError: LocalizedError {
    case unavailable(AIAvailability)
    case unsupportedOS
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let a): return a.headline
        case .unsupportedOS: return "Apple Intelligence requires macOS 26 or later."
        case .generationFailed(let msg): return msg
        }
    }
}

/// Thin facade over `FoundationModels` so the rest of the app can stay
/// agnostic of the framework's exact types.
final class AppleIntelligenceProvider {
    static let shared = AppleIntelligenceProvider()
    private init() {}

    /// Quick check the UI can use to decide whether to show the AI menu.
    var isPotentiallyAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// Detailed availability for the demo window header.
    func currentAvailability() -> AIAvailability {
        guard #available(macOS 26.0, *) else { return .osTooOld }
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                return .appleIntelligenceNotEnabled
            case .modelNotReady:
                return .modelNotReady
            case .deviceNotEligible:
                return .unsupportedDevice
            @unknown default:
                return .unknown(String(describing: reason))
            }
        @unknown default:
            return .unknown("Unexpected availability state")
        }
        #else
        return .osTooOld
        #endif
    }

    // MARK: - One-shot (non-streaming) generation

    /// Run the action and return the full result once generation finishes.
    func run(_ action: AIAction, on input: String) async throws -> String {
        guard #available(macOS 26.0, *) else { throw AIError.unsupportedOS }
        #if canImport(FoundationModels)
        let availability = currentAvailability()
        guard availability == .available else { throw AIError.unavailable(availability) }

        do {
            let session = LanguageModelSession(instructions: action.instructions)
            let response = try await session.respond(to: input)
            return response.content
        } catch {
            throw AIError.generationFailed(error.localizedDescription)
        }
        #else
        throw AIError.unsupportedOS
        #endif
    }

    // MARK: - Streaming generation

    /// Stream incremental text snapshots as the model generates them.
    /// Each yielded value is the *current full output so far*, so the UI
    /// can simply replace its result text on every update.
    func stream(_ action: AIAction, on input: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard #available(macOS 26.0, *) else {
                continuation.finish(throwing: AIError.unsupportedOS)
                return
            }
            #if canImport(FoundationModels)
            let availability = currentAvailability()
            guard availability == .available else {
                continuation.finish(throwing: AIError.unavailable(availability))
                return
            }

            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: action.instructions)
                    let stream = session.streamResponse(to: input)
                    for try await partial in stream {
                        // Different SDK versions expose the partial text under
                        // slightly different shapes. Try the common ones.
                        let text = Self.extractText(from: partial)
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AIError.generationFailed(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
            #else
            continuation.finish(throwing: AIError.unsupportedOS)
            #endif
        }
    }

    /// Best-effort extraction of the textual content from a streaming
    /// partial. Works whether the partial is a String, a struct with a
    /// `content` String, or has a `.text` property.
    private static func extractText(from partial: Any) -> String {
        if let s = partial as? String { return s }
        let mirror = Mirror(reflecting: partial)
        for child in mirror.children {
            if (child.label == "content" || child.label == "text"),
               let s = child.value as? String {
                return s
            }
        }
        return String(describing: partial)
    }
}
