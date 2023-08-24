import ActiveApplicationMonitor
import ChatService
import ComposableArchitecture
import Foundation
import GitHubCopilotService
import OpenAIService
import PromptToCodeService
import SuggestionModel
import SuggestionWidget

@MainActor
final class WidgetDataSource {
    final class PromptToCode {
        let promptToCodeService: PromptToCodeService
        let provider: PromptToCodeProvider
        public init(
            promptToCodeService: PromptToCodeService,
            provider: PromptToCodeProvider
        ) {
            self.promptToCodeService = promptToCodeService
            self.provider = provider
        }
    }

    private(set) var promptToCode: PromptToCode?

    init() {}

    @discardableResult
    func createPromptToCode(
        for url: URL,
        projectURL: URL,
        selectedCode: String,
        allCode: String,
        selectionRange: CursorRange,
        language: CodeLanguage,
        identSize: Int = 4,
        usesTabsForIndentation: Bool = false,
        extraSystemPrompt: String?,
        generateDescriptionRequirement: Bool?,
        name: String?
    ) async -> PromptToCodeService {
        let build = {
            let service = PromptToCodeService(
                code: selectedCode,
                selectionRange: selectionRange,
                language: language,
                identSize: identSize,
                usesTabsForIndentation: usesTabsForIndentation,
                projectRootURL: projectURL,
                fileURL: url,
                allCode: allCode,
                extraSystemPrompt: extraSystemPrompt,
                generateDescriptionRequirement: generateDescriptionRequirement
            )
            let provider = PromptToCodeProvider(
                service: service,
                name: name,
                onClosePromptToCode: { [weak self] in
                    self?.removePromptToCode()
                    let presenter = PresentInWindowSuggestionPresenter()
                    presenter.closePromptToCode(fileURL: url)
                    if let app = ActiveApplicationMonitor.shared.previousApp, app.isXcode {
                        Task { @MainActor in
                            try await Task.sleep(nanoseconds: 200_000_000)
                            app.activate()
                        }
                    }
                }
            )
            return PromptToCode(promptToCodeService: service, provider: provider)
        }

        let newPromptToCode = build()
        promptToCode = newPromptToCode
        return newPromptToCode.promptToCodeService
    }

    func removePromptToCode() {
        promptToCode = nil
    }

    func cleanup(for url: URL) {
//        removePromptToCode(for: url)
    }
}

extension WidgetDataSource: SuggestionWidgetDataSource {
    func suggestionForFile(at url: URL) async -> SuggestionProvider? {
        for workspace in Service.shared.workspacePool.workspaces.values {
            if let filespace = workspace.filespaces[url],
               let suggestion = filespace.presentingSuggestion
            {
                return .init(
                    code: suggestion.text,
                    language: filespace.language,
                    startLineIndex: suggestion.position.line,
                    suggestionCount: filespace.suggestions.count,
                    currentSuggestionIndex: filespace.suggestionIndex,
                    onSelectPreviousSuggestionTapped: {
                        Task {
                            let handler = PseudoCommandHandler()
                            await handler.presentPreviousSuggestion()
                        }
                    },
                    onSelectNextSuggestionTapped: {
                        Task {
                            let handler = PseudoCommandHandler()
                            await handler.presentNextSuggestion()
                        }
                    },
                    onRejectSuggestionTapped: {
                        Task {
                            let handler = PseudoCommandHandler()
                            await handler.rejectSuggestions()
                            if let app = ActiveApplicationMonitor.shared.previousApp,
                               app.isXcode
                            {
                                try await Task.sleep(nanoseconds: 200_000_000)
                                app.activate()
                            }
                        }
                    },
                    onAcceptSuggestionTapped: {
                        Task {
                            let handler = PseudoCommandHandler()
                            await handler.acceptSuggestion()
                            if let app = ActiveApplicationMonitor.shared.previousApp,
                               app.isXcode
                            {
                                try await Task.sleep(nanoseconds: 200_000_000)
                                app.activate()
                            }
                        }
                    }
                )
            }
        }
        return nil
    }

    func promptToCodeForFile(at url: URL) async -> PromptToCodeProvider? {
        return promptToCode?.provider
    }
}

