//
//  AppleIntelligenceProvider.swift
//  DynamicIsland
//
//  Thin wrapper around Apple's on-device FoundationModels framework
//  (Apple Intelligence). Runs entirely locally on the user's Mac.
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
    case osTooOld
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unsupportedDevice
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

    var isUsable: Bool { self == .available }
}

/// What the user wants the model to do with a piece of text.
enum AIAction: String, CaseIterable, Identifiable {
    case summarize
    case fixGrammar
    case shorten
    case expand
    case translateToEnglish
    case translateToHindi
    case explain
    case makeProfessional
    case makeFriendly
    case makeCasual
    case extractKeyPoints
    case replyAsEmail
    case convertToBullets
    case improveClarity
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summarize: return "Summarize"
        case .fixGrammar: return "Fix Grammar"
        case .shorten: return "Make Shorter"
        case .expand: return "Expand"
        case .translateToEnglish: return "→ English"
        case .translateToHindi: return "→ Hindi"
        case .explain: return "Explain Simply"
        case .makeProfessional: return "Professional"
        case .makeFriendly: return "Friendly"
        case .makeCasual: return "Casual"
        case .extractKeyPoints: return "Key Points"
        case .replyAsEmail: return "Draft Email Reply"
        case .convertToBullets: return "Bullet List"
        case .improveClarity: return "Improve Clarity"
        case .custom: return "Custom Prompt…"
        }
    }

    var shortTitle: String {
        switch self {
        case .summarize: return "Summary"
        case .fixGrammar: return "Grammar"
        case .shorten: return "Shorter"
        case .expand: return "Expand"
        case .translateToEnglish: return "EN"
        case .translateToHindi: return "HI"
        case .explain: return "Explain"
        case .makeProfessional: return "Pro"
        case .makeFriendly: return "Friendly"
        case .makeCasual: return "Casual"
        case .extractKeyPoints: return "Points"
        case .replyAsEmail: return "Reply"
        case .convertToBullets: return "Bullets"
        case .improveClarity: return "Clarity"
        case .custom: return "Custom"
        }
    }

    var symbolName: String {
        switch self {
        case .summarize: return "text.append"
        case .fixGrammar: return "checkmark.seal"
        case .shorten: return "arrow.down.right.and.arrow.up.left"
        case .expand: return "arrow.up.left.and.arrow.down.right"
        case .translateToEnglish: return "character.bubble"
        case .translateToHindi: return "character.bubble.fill"
        case .explain: return "lightbulb"
        case .makeProfessional: return "briefcase"
        case .makeFriendly: return "face.smiling"
        case .makeCasual: return "text.bubble"
        case .extractKeyPoints: return "list.bullet.rectangle"
        case .replyAsEmail: return "envelope"
        case .convertToBullets: return "list.bullet"
        case .improveClarity: return "wand.and.stars"
        case .custom: return "text.cursor"
        }
    }

    var category: AIActionCategory {
        switch self {
        case .summarize, .extractKeyPoints, .convertToBullets, .shorten, .expand, .improveClarity, .explain:
            return .rewrite
        case .fixGrammar, .makeProfessional, .makeFriendly, .makeCasual, .replyAsEmail:
            return .tone
        case .translateToEnglish, .translateToHindi:
            return .translate
        case .custom:
            return .custom
        }
    }

    /// Static role instructions (no user text). Kept short so they don't eat the 4k context window.
    var sessionInstructions: String {
        switch category {
        case .rewrite:
            return """
            You are a precise writing tool for a clipboard app.
            Follow the TASK in the prompt exactly.
            Never refuse ordinary writing tasks.
            Output ONLY the final result — no preamble, no quotes around the whole answer, no "Here is…".
            """
        case .tone:
            return """
            You are a tone/style rewriter for a clipboard app.
            Follow the TASK in the prompt exactly.
            Keep meaning and facts identical unless the task says otherwise.
            Output ONLY the rewritten text — no preamble.
            """
        case .translate:
            return """
            You are a professional translator for a clipboard app.
            Follow the TASK in the prompt exactly.
            Translate faithfully into natural target-language prose.
            Output ONLY the translation — no preamble, no notes.
            """
        case .custom:
            return """
            You are a helpful writing assistant for a clipboard app.
            Follow the user's custom TASK exactly as written.
            Use the SOURCE text as the material to work on.
            Output ONLY the final result — no preamble, no quotes around the whole answer.
            """
        }
    }

    /// Explicit per-action directive put INTO the prompt (this is what makes options differ).
    var taskDirective: String {
        switch self {
        case .summarize:
            return "TASK: Summarize the SOURCE text in 2–4 short sentences. Keep the same language as SOURCE."
        case .fixGrammar:
            return "TASK: Fix grammar, spelling, and punctuation in SOURCE. Keep meaning, tone, and language. Do not rewrite style beyond corrections."
        case .shorten:
            return "TASK: Rewrite SOURCE so it is ~50% shorter. Keep every important fact. Same language."
        case .expand:
            return "TASK: Expand SOURCE with clearer wording and a bit more detail. Do not invent facts. Same language."
        case .translateToEnglish:
            return "TASK: Translate SOURCE into natural English."
        case .translateToHindi:
            return "TASK: Translate SOURCE into natural Hindi (हिन्दी Devanagari script)."
        case .explain:
            return "TASK: Explain SOURCE in plain language a smart 12-year-old can understand. Use short sentences. Same language as SOURCE unless SOURCE is code/jargon in English."
        case .makeProfessional:
            return "TASK: Rewrite SOURCE in a clear professional business-email tone. Same language. Keep facts."
        case .makeFriendly:
            return "TASK: Rewrite SOURCE in a warm, friendly, conversational tone. Same language. Keep facts."
        case .makeCasual:
            return "TASK: Rewrite SOURCE in a casual everyday tone. Same language. Keep facts."
        case .extractKeyPoints:
            return "TASK: Extract 3–7 key points from SOURCE as a Markdown bullet list. One short bullet per point. Same language."
        case .replyAsEmail:
            return "TASK: Draft a polite concise email reply to SOURCE. Include a greeting and a sign-off like \"Best regards,\". Same language as SOURCE."
        case .convertToBullets:
            return "TASK: Convert SOURCE into a Markdown bullet list. One idea per bullet. Same language."
        case .improveClarity:
            return "TASK: Rewrite SOURCE so it is clearer and more direct. Same language. Keep meaning."
        case .custom:
            return "TASK: (provided by the user)"
        }
    }

    /// Sampling: precise tasks stay low-temp; creative rewrites get a little variety.
    var temperature: Double {
        switch self {
        case .fixGrammar, .translateToEnglish, .translateToHindi, .extractKeyPoints, .convertToBullets, .shorten:
            return 0.2
        case .summarize, .improveClarity, .makeProfessional, .explain:
            return 0.4
        case .expand, .makeFriendly, .makeCasual, .replyAsEmail, .custom:
            return 0.7
        }
    }

    /// Soft cap so summarize doesn't ramble. Kept generous — a tight cap truncates mid-sentence.
    var maxResponseTokens: Int {
        switch self {
        case .summarize, .extractKeyPoints, .convertToBullets, .shorten:
            return 400
        case .fixGrammar, .improveClarity, .makeProfessional, .makeFriendly, .makeCasual,
             .translateToEnglish, .translateToHindi:
            return 700
        case .explain, .expand, .replyAsEmail, .custom:
            return 900
        }
    }

    /// Build the full user prompt. Task is in the prompt so each option is unmistakably different.
    /// Pass `customPrompt` when `self == .custom`.
    func makePrompt(for source: String, customPrompt: String? = nil) -> String {
        let directive: String
        if self == .custom {
            let userTask = customPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            directive = "TASK: \(userTask.isEmpty ? "Process the SOURCE text helpfully." : userTask)"
        } else {
            directive = taskDirective
        }

        return """
        \(directive)

        SOURCE:
        \"\"\"
        \(source)
        \"\"\"

        Reminder: output ONLY the result for the TASK above.
        """
    }
}

enum AIActionCategory: String, CaseIterable {
    case rewrite
    case tone
    case translate
    case custom

    var title: String {
        switch self {
        case .rewrite: return "Rewrite"
        case .tone: return "Tone"
        case .translate: return "Translate"
        case .custom: return "Custom"
        }
    }
}

enum AIError: LocalizedError {
    case unavailable(AIAvailability)
    case unsupportedOS
    case emptyInput
    case emptyCustomPrompt
    case inputTooLong(Int)
    case generationFailed(String)
    case cancelled
    case busy

    var errorDescription: String? {
        switch self {
        case .unavailable(let a): return a.headline
        case .unsupportedOS: return "Apple Intelligence requires macOS 26 or later."
        case .emptyInput: return "Nothing to process — paste some text first."
        case .emptyCustomPrompt: return "Enter a custom prompt first (e.g. “Turn this into a tweet”)."
        case .inputTooLong(let max): return "Text is too long for on-device AI (max ~\(max) characters). Try a shorter selection."
        case .generationFailed(let msg): return msg
        case .cancelled: return "Cancelled"
        case .busy: return "Apple Intelligence is still finishing the previous request."
        }
    }
}

/// A throttled text snapshot from the model, tagged with a generation id
/// so the UI can ignore stale updates after the user switches actions.
struct AIStreamUpdate: Sendable {
    let generationID: UInt64
    let text: String
    let isFinal: Bool
}

/// Thin facade over `FoundationModels`.
final class AppleIntelligenceProvider {
    static let shared = AppleIntelligenceProvider()
    private init() {}

    /// On-device context is ~4096 tokens total (instructions + prompt + response).
    /// Keep source text well under that so options stay reliable.
    static let maxInputCharacters = 3_500

    /// UI should refresh at most this often while streaming (keeps the panel smooth).
    static let uiThrottleNanoseconds: UInt64 = 50_000_000 // 50ms ≈ 20 fps

    private let generationLock = NSLock()
    private var generationCounter: UInt64 = 0
    private var activeGenerationID: UInt64 = 0

    var isPotentiallyAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

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

    func prepareInput(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.emptyInput }
        if trimmed.count > Self.maxInputCharacters {
            throw AIError.inputTooLong(Self.maxInputCharacters)
        }
        return trimmed
    }

    /// Bump the generation counter and mark this id as the only live one.
    @discardableResult
    func beginGeneration() -> UInt64 {
        generationLock.lock()
        generationCounter &+= 1
        activeGenerationID = generationCounter
        let id = activeGenerationID
        generationLock.unlock()
        return id
    }

    func isCurrentGeneration(_ id: UInt64) -> Bool {
        generationLock.lock()
        let ok = activeGenerationID == id
        generationLock.unlock()
        return ok
    }

    func cancelGeneration(_ id: UInt64) {
        generationLock.lock()
        if activeGenerationID == id {
            activeGenerationID = 0
        }
        generationLock.unlock()
    }

    // MARK: - One-shot

    func run(_ action: AIAction, on input: String, customPrompt: String? = nil) async throws -> String {
        guard #available(macOS 26.0, *) else { throw AIError.unsupportedOS }
        #if canImport(FoundationModels)
        let availability = currentAvailability()
        guard availability.isUsable else { throw AIError.unavailable(availability) }
        let source = try prepareInput(input)
        if action == .custom {
            let trimmed = customPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty { throw AIError.emptyCustomPrompt }
        }
        let generationID = beginGeneration()
        defer { cancelGeneration(generationID) }

        do {
            let session = LanguageModelSession(instructions: action.sessionInstructions)
            let options = GenerationOptions(
                temperature: action.temperature,
                maximumResponseTokens: action.maxResponseTokens
            )
            let response = try await session.respond(
                to: action.makePrompt(for: source, customPrompt: customPrompt),
                options: options
            )
            guard isCurrentGeneration(generationID) else { throw AIError.cancelled }
            return response.content
        } catch is CancellationError {
            throw AIError.cancelled
        } catch let err as AIError {
            throw err
        } catch {
            throw AIError.generationFailed(Self.friendlyMessage(for: error))
        }
        #else
        throw AIError.unsupportedOS
        #endif
    }

    // MARK: - Streaming

    /// Streams cumulative text snapshots. Yields are throttled so the UI stays responsive.
    /// Pass `customPrompt` when `action == .custom`.
    func stream(_ action: AIAction, on input: String, customPrompt: String? = nil) -> AsyncThrowingStream<AIStreamUpdate, Error> {
        AsyncThrowingStream { continuation in
            guard #available(macOS 26.0, *) else {
                continuation.finish(throwing: AIError.unsupportedOS)
                return
            }
            #if canImport(FoundationModels)
            let availability = currentAvailability()
            guard availability.isUsable else {
                continuation.finish(throwing: AIError.unavailable(availability))
                return
            }

            let source: String
            do {
                source = try prepareInput(input)
            } catch {
                continuation.finish(throwing: error)
                return
            }

            if action == .custom {
                let trimmed = customPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if trimmed.isEmpty {
                    continuation.finish(throwing: AIError.emptyCustomPrompt)
                    return
                }
            }

            let generationID = beginGeneration()
            let prompt = action.makePrompt(for: source, customPrompt: customPrompt)
            let instructions = action.sessionInstructions
            let temperature = action.temperature
            let maxTokens = action.maxResponseTokens

            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    // Warm the KV cache while we set up — cuts first-token latency.
                    session.prewarm()

                    let options = GenerationOptions(
                        temperature: temperature,
                        maximumResponseTokens: maxTokens
                    )
                    let stream = session.streamResponse(to: prompt, options: options)

                    var lastYield = ContinuousClock.now
                    var latestText = ""

                    for try await partial in stream {
                        if Task.isCancelled || !self.isCurrentGeneration(generationID) {
                            continuation.finish(throwing: AIError.cancelled)
                            return
                        }

                        let text = Self.textFromPartial(partial.content)
                        guard !text.isEmpty else { continue }
                        latestText = text

                        let now = ContinuousClock.now
                        let elapsed = now - lastYield
                        if elapsed >= .nanoseconds(Int64(Self.uiThrottleNanoseconds)) {
                            lastYield = now
                            continuation.yield(AIStreamUpdate(
                                generationID: generationID,
                                text: latestText,
                                isFinal: false
                            ))
                        }
                    }

                    if Task.isCancelled || !self.isCurrentGeneration(generationID) {
                        continuation.finish(throwing: AIError.cancelled)
                        return
                    }

                    if !latestText.isEmpty {
                        continuation.yield(AIStreamUpdate(
                            generationID: generationID,
                            text: latestText,
                            isFinal: true
                        ))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AIError.cancelled)
                } catch {
                    if !self.isCurrentGeneration(generationID) {
                        continuation.finish(throwing: AIError.cancelled)
                    } else {
                        continuation.finish(throwing: AIError.generationFailed(Self.friendlyMessage(for: error)))
                    }
                }
            }

            continuation.onTermination = { [weak self] reason in
                task.cancel()
                // Only invalidate the generation id when the consumer cancelled.
                // On a normal finish we leave it current so the UI can still
                // recognize the completed run until the next beginGeneration().
                if case .cancelled = reason {
                    self?.cancelGeneration(generationID)
                }
            }
            #else
            continuation.finish(throwing: AIError.unsupportedOS)
            #endif
        }
    }

    private static func friendlyMessage(for error: Error) -> String {
        let raw = error.localizedDescription
        let lower = raw.lowercased()
        if lower.contains("exceed") || lower.contains("context") || lower.contains("token") {
            return "Text is too long for the on-device model. Try a shorter selection."
        }
        if lower.contains("cancel") {
            return "Cancelled"
        }
        if lower.contains("not available") || lower.contains("unavailable") {
            return "Apple Intelligence became unavailable mid-run. Check System Settings."
        }
        if lower.contains("responding") || lower.contains("busy") {
            return "Still working on the previous request — try again in a second."
        }
        return raw.isEmpty ? "Generation failed." : raw
    }

    private static func textFromPartial(_ value: Any) -> String {
        if let s = value as? String { return s }
        let mirror = Mirror(reflecting: value)
        for child in mirror.children {
            if let s = child.value as? String,
               child.label == nil || child.label == "content" || child.label == "text" {
                return s
            }
        }
        let described = String(describing: value)
        if described == "nil"
            || described.hasPrefix("Optional(")
            || described.contains("PartiallyGenerated") {
            return ""
        }
        return described
    }
}
