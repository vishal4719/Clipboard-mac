//
//  AIDemoWindow.swift
//  DynamicIsland
//
//  A small NSPanel that lets the user paste any text, pick an action,
//  and watch Apple Intelligence stream a response in real time. Used
//  as a sandbox to *see* on-device AI working before wiring it into
//  the rest of the app.
//

import AppKit

final class AIDemoWindow: NSPanel, NSTextViewDelegate {

    // MARK: - Singleton-ish presenter

    private static var current: AIDemoWindow?

    static func show() {
        show(prefillText: nil, autoRun: nil, customPrompt: nil)
    }

    /// Open the demo window. Optionally seed it with input text and
    /// kick off a specific action immediately so the user lands on a
    /// streaming response.
    static func show(prefillText: String?, autoRun: AIAction?, customPrompt: String? = nil) {
        let win: AIDemoWindow
        if let existing = current {
            win = existing
        } else {
            win = AIDemoWindow()
            current = win
            win.center()
        }

        if let text = prefillText, !text.isEmpty {
            win.inputTextView.string = text
            win.resultTextView.string = ""
        }
        if let prompt = customPrompt, !prompt.isEmpty {
            win.customPromptField.stringValue = prompt
        }
        if let action = autoRun {
            win.selectedAction = action
            win.updateActionSelection()
        }

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let action = autoRun, let text = prefillText, !text.isEmpty {
            // Defer one runloop so the window has a chance to lay out before
            // we kick off streaming (otherwise the spinner can pop in awkwardly).
            // For Custom, only auto-run when a prompt was supplied.
            if action != .custom || !(customPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                DispatchQueue.main.async { [weak win] in
                    win?.startRun(input: text)
                }
            }
        }
    }

    // MARK: - Subviews

    private let availabilityBadge = NSTextField(labelWithString: "")
    private let availabilityHint = NSTextField(labelWithString: "")
    private var inputTextView: NSTextView!
    private var resultTextView: NSTextView!
    private let customPromptField = NSTextField(string: "")
    private let customPromptLabel = NSTextField(labelWithString: "Custom prompt")
    private let actionsStack = NSStackView()
    private let runButton = NSButton(title: "Run", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Stop", target: nil, action: nil)
    private let copyResultButton = NSButton(title: "Copy Result", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let progressIndicator = NSProgressIndicator()

    private var selectedAction: AIAction = .summarize
    private var actionButtons: [AIAction: NSButton] = [:]
    private var currentTask: Task<Void, Never>?
    private var runToken = UUID()

    // MARK: - Init

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        title = "Apple Intelligence"
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        minSize = NSSize(width: 560, height: 520)
        delegate = self
        setupContent()
        refreshAvailability()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    deinit {
        if AIDemoWindow.current === self {
            AIDemoWindow.current = nil
        }
    }

    // MARK: - Layout

    private func setupContent() {
        guard let content = contentView else { return }

        // Liquid-glass background — tracks system light/dark
        let visual = NSVisualEffectView(frame: content.bounds)
        visual.autoresizingMask = [.width, .height]
        LiquidGlass.applyChrome(to: visual, bounds: content.bounds, cornerRadius: 16)
        content.addSubview(visual)

        let root = NSView(frame: content.bounds)
        root.autoresizingMask = [.width, .height]
        root.translatesAutoresizingMaskIntoConstraints = true
        content.addSubview(root)

        // Header
        let titleLabel = NSTextField(labelWithString: "Apple Intelligence")
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = LiquidGlass.primaryText

        let subtitleLabel = NSTextField(labelWithString: "On-device · Private · Free")
        subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        subtitleLabel.textColor = LiquidGlass.secondaryText

        let headerStack = NSStackView(views: [titleLabel, subtitleLabel])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 2

        availabilityBadge.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        availabilityBadge.textColor = .labelColor

        availabilityHint.font = NSFont.systemFont(ofSize: 11)
        availabilityHint.textColor = .secondaryLabelColor
        availabilityHint.lineBreakMode = .byWordWrapping
        availabilityHint.maximumNumberOfLines = 0

        let availabilityStack = NSStackView(views: [availabilityBadge, availabilityHint])
        availabilityStack.orientation = .vertical
        availabilityStack.alignment = .leading
        availabilityStack.spacing = 1

        let topSpacer = NSView()
        topSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let topRow = NSStackView(views: [headerStack, topSpacer, availabilityStack])
        topRow.orientation = .horizontal
        topRow.alignment = .top
        topRow.distribution = .fill

        // Input
        let inputLabel = NSTextField(labelWithString: "Your text")
        inputLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        inputLabel.textColor = .secondaryLabelColor

        let inputScroll = makeTextScrollView(editable: true)
        inputTextView = inputScroll.documentView as? NSTextView
        inputTextView.delegate = self
        inputTextView.string = "Paste any text here. Try a long paragraph to see Summarize work, " +
            "or a sentence with mistakes to see grammar fixing."

        // Action buttons
        let actionLabel = NSTextField(labelWithString: "Action")
        actionLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        actionLabel.textColor = .secondaryLabelColor

        actionsStack.orientation = .horizontal
        actionsStack.spacing = 6
        actionsStack.alignment = .centerY
        actionsStack.distribution = .fillEqually
        actionsStack.translatesAutoresizingMaskIntoConstraints = false

        // Group actions by category so the expanded set stays scannable
        let actionsContainer = NSStackView()
        actionsContainer.orientation = .vertical
        actionsContainer.spacing = 8
        actionsContainer.alignment = .leading
        actionsContainer.distribution = .fill
        actionsContainer.translatesAutoresizingMaskIntoConstraints = false

        for category in AIActionCategory.allCases {
            let catLabel = NSTextField(labelWithString: category.title.uppercased())
            catLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            catLabel.textColor = .tertiaryLabelColor

            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 6
            row.distribution = .fillProportionally
            row.alignment = .centerY
            row.translatesAutoresizingMaskIntoConstraints = false

            for action in AIAction.allCases where action.category == category {
                let btn = makeActionButton(for: action)
                actionButtons[action] = btn
                row.addArrangedSubview(btn)
            }

            let catStack = NSStackView(views: [catLabel, row])
            catStack.orientation = .vertical
            catStack.spacing = 4
            catStack.alignment = .leading
            actionsContainer.addArrangedSubview(catStack)
            row.widthAnchor.constraint(equalTo: actionsContainer.widthAnchor).isActive = true
        }

        // Custom prompt (shown when Custom action is selected)
        customPromptLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        customPromptLabel.textColor = .secondaryLabelColor
        customPromptField.placeholderString = "e.g. Turn this into a short LinkedIn post"
        customPromptField.font = NSFont.systemFont(ofSize: 13)
        customPromptField.isHidden = true
        customPromptLabel.isHidden = true

        // Result
        let resultLabel = NSTextField(labelWithString: "Result")
        resultLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        resultLabel.textColor = .secondaryLabelColor

        let resultScroll = makeTextScrollView(editable: false)
        resultTextView = resultScroll.documentView as? NSTextView

        // Footer buttons
        runButton.bezelStyle = .rounded
        runButton.controlSize = .large
        runButton.keyEquivalent = "\r"
        runButton.target = self
        runButton.action = #selector(runTapped)
        if let cell = runButton.cell as? NSButtonCell { cell.imageScaling = .scaleProportionallyDown }
        runButton.title = "  Run \(selectedAction.title)  "
        runButton.bezelColor = NSColor.controlAccentColor

        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .large
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.isEnabled = false

        copyResultButton.bezelStyle = .rounded
        copyResultButton.controlSize = .large
        copyResultButton.target = self
        copyResultButton.action = #selector(copyResultTapped)

        clearButton.bezelStyle = .rounded
        clearButton.controlSize = .large
        clearButton.target = self
        clearButton.action = #selector(clearTapped)

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [progressIndicator, clearButton, copyResultButton, footerSpacer, cancelButton, runButton])
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.alignment = .centerY

        // Vertical assembly
        let mainStack = NSStackView(views: [
            topRow,
            inputLabel, inputScroll,
            actionLabel, actionsContainer,
            customPromptLabel, customPromptField,
            resultLabel, resultScroll,
            footer
        ])
        mainStack.orientation = .vertical
        mainStack.spacing = 8
        mainStack.alignment = .leading
        mainStack.distribution = .fill
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        mainStack.setCustomSpacing(14, after: topRow)
        mainStack.setCustomSpacing(4, after: inputLabel)
        mainStack.setCustomSpacing(12, after: inputScroll)
        mainStack.setCustomSpacing(4, after: actionLabel)
        mainStack.setCustomSpacing(12, after: actionsContainer)
        mainStack.setCustomSpacing(4, after: customPromptLabel)
        mainStack.setCustomSpacing(12, after: customPromptField)
        mainStack.setCustomSpacing(4, after: resultLabel)
        mainStack.setCustomSpacing(12, after: resultScroll)

        root.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 36),
            mainStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            mainStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),

            inputScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 90),
            resultScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 130),
            inputScroll.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            resultScroll.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            actionsContainer.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            customPromptField.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            topRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])

        updateActionSelection()
    }

    /// Build a styled, scrollable NSTextView wrapped in NSScrollView.
    private func makeTextScrollView(editable: Bool) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 8
        scroll.layer?.cornerCurve = .continuous
        scroll.layer?.borderWidth = 0.5
        scroll.layer?.borderColor = NSColor.separatorColor.cgColor
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.5)
        if let tv = scroll.documentView as? NSTextView {
            tv.font = NSFont.systemFont(ofSize: 13)
            tv.isEditable = editable
            tv.isRichText = false
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.isAutomaticDashSubstitutionEnabled = false
            tv.textColor = .labelColor
            tv.drawsBackground = false
            tv.textContainerInset = NSSize(width: 8, height: 8)
            tv.allowsUndo = editable
        }
        return scroll
    }

    private func makeActionButton(for action: AIAction) -> NSButton {
        let btn = NSButton(title: action.title, target: self, action: #selector(actionTapped(_:)))
        btn.bezelStyle = .rounded
        btn.controlSize = .regular
        btn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        btn.image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: action.title)
        btn.imagePosition = .imageLeading
        btn.imageScaling = .scaleProportionallyDown
        btn.identifier = NSUserInterfaceItemIdentifier(action.rawValue)
        btn.setButtonType(.pushOnPushOff)
        return btn
    }

    // MARK: - State

    private func refreshAvailability() {
        let availability = AppleIntelligenceProvider.shared.currentAvailability()
        availabilityBadge.stringValue = availability.headline
        availabilityHint.stringValue = availability.hint
        let ok = availability == .available
        availabilityBadge.textColor = ok ? .systemGreen : .systemOrange
        runButton.isEnabled = ok
        for (_, b) in actionButtons { b.isEnabled = ok }
    }

    private func updateActionSelection() {
        for (action, button) in actionButtons {
            button.state = (action == selectedAction) ? .on : .off
        }
        let isCustom = selectedAction == .custom
        customPromptLabel.isHidden = !isCustom
        customPromptField.isHidden = !isCustom
        runButton.title = isCustom ? "  Run Custom Prompt  " : "  Run \(selectedAction.title)  "
        if isCustom {
            makeFirstResponder(customPromptField)
        }
    }

    private func appendOrReplaceResult(_ text: String) {
        resultTextView.string = text
        resultTextView.scrollToEndOfDocument(nil)
    }

    // MARK: - Actions

    @objc private func actionTapped(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let action = AIAction(rawValue: id) else { return }
        let changed = action != selectedAction
        selectedAction = action
        updateActionSelection()
        // Re-run automatically when switching actions with existing input,
        // so users immediately see a *different* result for the new option.
        if changed {
            let input = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !input.isEmpty, AppleIntelligenceProvider.shared.currentAvailability().isUsable {
                startRun(input: input)
            }
        }
    }

    @objc private func runTapped() {
        let input = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            NSSound.beep()
            return
        }
        if selectedAction == .custom {
            let prompt = customPromptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else {
                NSSound.beep()
                makeFirstResponder(customPromptField)
                return
            }
        }
        startRun(input: input)
    }

    @objc private func cancelTapped() {
        runToken = UUID() // invalidate any late stream updates
        currentTask?.cancel()
        currentTask = nil
        progressIndicator.stopAnimation(nil)
        cancelButton.isEnabled = false
        runButton.isEnabled = true
    }

    @objc private func copyResultTapped() {
        let text = resultTextView.string
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        ClipboardManager.shared.acknowledgeSelfWrite()
    }

    @objc private func clearTapped() {
        inputTextView.string = ""
        resultTextView.string = ""
    }

    private func startRun(input: String) {
        currentTask?.cancel()
        currentTask = nil

        let token = UUID()
        runToken = token
        resultTextView.string = "…"
        progressIndicator.startAnimation(nil)
        cancelButton.isEnabled = true
        runButton.isEnabled = false

        let action = selectedAction
        let custom = (action == .custom)
            ? customPromptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        currentTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let stream = AppleIntelligenceProvider.shared.stream(action, on: input, customPrompt: custom)
                for try await update in stream {
                    if Task.isCancelled { return }
                    await MainActor.run {
                        guard self.runToken == token else { return }
                        self.appendOrReplaceResult(update.text)
                    }
                }
            } catch {
                if Task.isCancelled { return }
                if let aiErr = error as? AIError, case .cancelled = aiErr { return }
                let message: String
                if let aiErr = error as? AIError {
                    message = aiErr.errorDescription ?? "\(error)"
                } else {
                    message = error.localizedDescription
                }
                await MainActor.run {
                    guard self.runToken == token else { return }
                    self.resultTextView.string = "⚠️ \(message)"
                }
            }
            await MainActor.run {
                guard self.runToken == token else { return }
                self.progressIndicator.stopAnimation(nil)
                self.cancelButton.isEnabled = false
                self.runButton.isEnabled = true
                self.refreshAvailability()
            }
        }
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        // No-op for now; placeholder for future "auto-run" toggle.
    }
}

// MARK: - Window lifecycle

extension AIDemoWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        currentTask?.cancel()
        currentTask = nil
        if AIDemoWindow.current === self {
            AIDemoWindow.current = nil
        }
    }
}
