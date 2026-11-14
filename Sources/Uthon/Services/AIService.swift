import Foundation
import SwiftUI
import AppKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The on-device language model (Apple Intelligence, macOS 26+). Everything runs on this
/// Mac: no account, no key, nothing is sent anywhere.
final class AIService: ObservableObject {
    static let shared = AIService()

    enum Availability: Equatable {
        case available
        case needsNewerMacOS
        case notEnabled
        case deviceNotEligible
        case notReady
        case other

        var message: String {
            switch self {
            case .available: return "Ready, running on this Mac"
            case .needsNewerMacOS: return "Needs macOS 26 or later"
            case .notEnabled: return "Turn on Apple Intelligence in System Settings"
            case .deviceNotEligible: return "This Mac does not support Apple Intelligence"
            case .notReady: return "Apple Intelligence is still getting ready (downloading)"
            case .other: return "Apple Intelligence is not available right now"
            }
        }
    }

    @Published private(set) var busy = false
    /// A job handed over from elsewhere (e.g. "translate what I copied"), run by the AI tab.
    @Published var pending: (text: String, action: AIAction)?

    var availability: Availability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return .deviceNotEligible
                case .appleIntelligenceNotEnabled: return .notEnabled
                case .modelNotReady: return .notReady
                @unknown default: return .other
                }
            }
        }
        #endif
        return .needsNewerMacOS
    }

    var isAvailable: Bool { availability == .available }

    enum AIError: Error { case unavailable }

    /// The language the answer should be in, from Settings ("auto" follows Nook's language).
    static var answerLanguage: String {
        switch UserLibrary.shared.aiAnswerLanguage {
        case "bn": return "Bangla"
        case "en": return "English"
        default: return Localization.isBangla ? "Bangla" : "English"
        }
    }

    /// One question, one answer. The instructions are put in front of the request.
    func ask(_ request: String, instructions: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            await MainActor.run { busy = true }
            defer { Task { @MainActor in self.busy = false } }
            let session = LanguageModelSession()
            let response = try await session.respond(to: instructions + "\n\n" + request)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw AIError.unavailable
    }

    func openAppleIntelligenceSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Ready-made jobs for the assistant.
enum AIAction: String, CaseIterable, Identifiable {
    case answer, summarize, fixGrammar, toBangla, toEnglish, reply, explain
    var id: String { rawValue }

    var title: String {
        switch self {
        case .answer: return "Ask"
        case .summarize: return "Summarize"
        case .fixGrammar: return "Fix writing"
        case .toBangla: return "To Bangla"
        case .toEnglish: return "To English"
        case .reply: return "Write a reply"
        case .explain: return "Explain simply"
        }
    }

    var symbol: String {
        switch self {
        case .answer: return "sparkles"
        case .summarize: return "text.redaction"
        case .fixGrammar: return "checkmark.seal"
        case .toBangla, .toEnglish: return "character.bubble"
        case .reply: return "arrowshape.turn.up.left"
        case .explain: return "lightbulb"
        }
    }

    func instructions(language: String) -> String {
        switch self {
        case .answer: return "You are a helpful assistant on a Mac. Answer clearly and briefly in \(language)."
        case .summarize: return "Summarize the following text in 2-4 short sentences in \(language). Keep names and numbers."
        case .fixGrammar: return "Correct the spelling and grammar of the following text. Keep its language and meaning. Reply with the corrected text only."
        case .toBangla: return "Translate the following text into natural Bangla. Reply with the translation only."
        case .toEnglish: return "Translate the following text into natural English. Reply with the translation only."
        case .reply: return "Write a short, polite reply to the following message, in the same language as the message. Reply with the message only."
        case .explain: return "Explain the following in simple words in \(language), in a few sentences."
        }
    }
}

// MARK: Island tab

struct IslandAssistant: View {
    @ObservedObject private var ai = AIService.shared
    @ObservedObject private var clipboard = ClipboardStore.shared
    @State private var input = ""
    @State private var output = ""
    @State private var error: String?
    @State private var copied = false
    @FocusState private var focused: Bool

    private var clipText: String? {
        clipboard.items.first { !$0.isImage }?.text
    }

    var body: some View {
        if ai.isAvailable {
            assistant
        } else {
            VStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 24, weight: .light)).foregroundStyle(Theme.accent)
                Text(L(ai.availability.message)).font(.system(size: 12, weight: .medium))
                Text(L("The assistant uses Apple Intelligence on this Mac: private, free and offline."))
                    .font(.system(size: 10)).foregroundStyle(Color.secondary)
                if ai.availability == .notEnabled {
                    Button(L("Open Apple Intelligence settings")) { ai.openAppleIntelligenceSettings() }
                        .buttonStyle(AccentButtonStyle())
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var assistant: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                    TextField(L("Ask anything, or pick a job for the copied text…"), text: $input)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .focused($focused)
                        .onSubmit { run(.answer) }
                    if ai.busy { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassChip(radius: 14)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(AIAction.allCases.filter { $0 != .answer }) { action in
                            Button { run(action) } label: {
                                Label(L(action.title), systemImage: action.symbol)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                            .disabled(ai.busy || (input.isEmpty && clipText == nil))
                        }
                    }
                }
                Text(input.isEmpty
                     ? (clipText.map { L("Uses the copied text:") + " " + String($0.prefix(60)) } ?? L("Copy some text or type above."))
                     : L("Uses what you typed."))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            .frame(width: 300)
            VStack(alignment: .leading, spacing: 6) {
                ScrollView {
                    Text(error ?? (output.isEmpty ? L("The answer appears here.") : output))
                        .font(.system(size: 12))
                        .foregroundStyle(output.isEmpty || error != nil ? Color.secondary : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .textSelection(.enabled)
                }
                if !output.isEmpty {
                    HStack {
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(output, forType: .string)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                        } label: {
                            Label(L(copied ? "Copied" : "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassChip(radius: 16)
        }
        .onAppear {
            focused = true
            takePending()
        }
        .onReceive(ai.$pending) { _ in takePending() }
    }

    private func takePending() {
        guard let job = ai.pending else { return }
        ai.pending = nil
        input = job.text
        run(job.action)
    }

    private func run(_ action: AIAction) {
        let text = input.isEmpty ? (clipText ?? "") : input
        guard !text.isEmpty, !ai.busy else { return }
        error = nil
        output = ""
        let instructions = action.instructions(language: AIService.answerLanguage)
        Task {
            do {
                let answer = try await ai.ask(text, instructions: instructions)
                await MainActor.run { output = answer }
            } catch {
                await MainActor.run { self.error = L("Could not answer that. Try rephrasing.") }
            }
        }
    }
}
