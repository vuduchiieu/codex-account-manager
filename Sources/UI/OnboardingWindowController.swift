import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private let model: AppModel
    private var controller: NSWindowController?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if let window = controller?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: OnboardingView(
            model: model,
            onComplete: { [weak self] in self?.close() }
        ))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "LLM Account Switcher"
        window.styleMask = [.titled, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 620, height: 470))
        window.minSize = NSSize(width: 620, height: 470)
        window.maxSize = NSSize(width: 620, height: 470)
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        self.controller = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func close() {
        controller?.close()
        controller = nil
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case provider
    case binary
    case login
}

private struct OnboardingView: View {
    @Bindable var model: AppModel
    let onComplete: () -> Void

    @State private var localization = LocalizationManager.shared
    @State private var step: OnboardingStep = .provider
    @State private var selectedProvider: LLMProvider?
    @State private var isResolvingBinary = false

    private var supportedProviders: [LLMProvider] {
        LLMProvider.allCases.filter(\.isAvailable)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 44)
                .padding(.vertical, 28)
            Divider()
            footer
        }
        .frame(width: 620, height: 470)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("LLM Account Switcher")
                    .font(.title2.weight(.bold))
                Text(localization.text("onboarding_title"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 7) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.22))
                        .frame(width: item == step ? 24 : 8, height: 8)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .provider:
            providerStep
        case .binary:
            binaryStep
        case .login:
            loginStep
        }
    }

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeading(
                localization.text("onboarding_choose_provider"),
                localization.text("onboarding_choose_provider_description")
            )

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                spacing: 14
            ) {
                ForEach(supportedProviders) { provider in
                    Button {
                        selectedProvider = provider
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: provider.systemImage)
                                    .font(.system(size: 24, weight: .medium))
                                Spacer()
                                Image(systemName: selectedProvider == provider ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(selectedProvider == provider ? Color.accentColor : Color.secondary)
                            }
                            Text(provider.name)
                                .font(.headline.weight(.semibold))
                            Text(providerSubtitle(provider))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
                        .background(
                            selectedProvider == provider ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    selectedProvider == provider ? Color.accentColor : Color(nsColor: .separatorColor),
                                    lineWidth: selectedProvider == provider ? 1.5 : 0.5
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var binaryStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeading(
                localization.text("onboarding_binary_title"),
                localization.format("onboarding_binary_description", selectedProvider?.name ?? "")
            )

            HStack(spacing: 14) {
                Image(systemName: "terminal")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.text("binary_path"))
                        .font(.headline)
                    if isResolvingBinary {
                        Text(localization.text("onboarding_detecting_binary"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(binaryPath ?? localization.text("not_configured"))
                            .font(.caption)
                            .foregroundStyle(binaryPath == nil ? .red : .secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 12)
                if isResolvingBinary {
                    ProgressView().controlSize(.small)
                } else {
                    Button(localization.text("onboarding_change_path"), action: chooseBinary)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .focusable(false)
                }
            }
            .padding(18)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }

            if !isResolvingBinary, binaryPath == nil {
                Label(localization.text("onboarding_binary_not_found"), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var loginStep: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Image(systemName: selectedProvider?.systemImage ?? "person.crop.circle")
                .font(.system(size: 46, weight: .medium))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 8) {
                Text(localization.format("onboarding_sign_in_title", selectedProvider?.name ?? ""))
                    .font(.title2.weight(.bold))
                Text(localization.text("onboarding_sign_in_description"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 390)
            }
            if isSigningIn {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(localization.text(loginMessageKey))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if selectedProvider == .codex {
                        Button(localization.text("cancel"), role: .cancel) {
                            model.cancelAddAccount()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack {
            if step != .provider {
                backButton
            }
            Spacer()
            primaryButton
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    @ViewBuilder private var backButton: some View {
        if #available(macOS 26.0, *) {
            Button(localization.text("onboarding_back"), action: goBack)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .disabled(isResolvingBinary || isSigningIn)
        } else {
            Button(localization.text("onboarding_back"), action: goBack)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .disabled(isResolvingBinary || isSigningIn)
        }
    }

    @ViewBuilder private var primaryButton: some View {
        if #available(macOS 26.0, *) {
            Button(primaryButtonTitle, action: primaryAction)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .disabled(!canContinue)
        } else {
            Button(primaryButtonTitle, action: primaryAction)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(!canContinue)
        }
    }

    private func goBack() {
        step = OnboardingStep(rawValue: step.rawValue - 1) ?? .provider
    }

    private func stepHeading(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.title2.weight(.bold))
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var binaryPath: String? {
        switch selectedProvider {
        case .codex: model.state.codexBinaryPath
        case .claude: model.state.claudeBinaryPath
        case .cursor: model.state.cursorBinaryPath
        case .antigravity: model.state.antigravityBinaryPath
        case .copilot: model.state.copilotBinaryPath
        case nil: nil
        }
    }

    private var isSigningIn: Bool {
        switch selectedProvider {
        case .codex: model.isAddingAccount
        case .claude: model.isAddingClaudeAccount
        case .cursor: model.isAddingCursorAccount
        case .antigravity: model.isAddingAntigravityAccount
        case .copilot: model.isAddingCopilotAccount
        case nil: false
        }
    }

    private var loginMessageKey: String {
        switch selectedProvider {
        case .codex: model.loginMessageKey ?? "waiting_login"
        case .claude: "waiting_claude_login"
        case .cursor: "waiting_cursor_login"
        case .antigravity: "waiting_antigravity_login"
        case .copilot: "waiting_copilot_login"
        case nil: "waiting_login"
        }
    }

    private var primaryButtonTitle: String {
        step == .login ? localization.text("onboarding_sign_in") : localization.text("onboarding_continue")
    }

    private var canContinue: Bool {
        switch step {
        case .provider: selectedProvider != nil && !isResolvingBinary
        case .binary: binaryPath != nil && !isResolvingBinary
        case .login: !isSigningIn
        }
    }

    private func primaryAction() {
        switch step {
        case .provider:
            guard let selectedProvider else { return }
            isResolvingBinary = true
            Task {
                switch selectedProvider {
                case .codex:
                    await model.resolveBinary()
                case .claude:
                    await model.resolveClaudeBinary()
                case .cursor:
                    await model.resolveCursorBinary()
                case .antigravity:
                    await model.resolveAntigravityBinary()
                case .copilot:
                    await model.resolveCopilotBinary()
                }
                isResolvingBinary = false
                step = .binary
            }
        case .binary:
            step = .login
        case .login:
            startLogin()
        }
    }

    private func chooseBinary() {
        switch selectedProvider {
        case .codex: model.chooseBinary()
        case .claude: model.chooseClaudeBinary()
        case .cursor: model.chooseCursorBinary()
        case .antigravity: model.chooseAntigravityBinary()
        case .copilot: model.chooseCopilotBinary()
        case nil: break
        }
    }

    private func startLogin() {
        switch selectedProvider {
        case .codex:
            model.addAccount(onSuccess: finish)
        case .claude:
            model.addClaudeAccount(onSuccess: finish)
        case .cursor:
            model.addCursorAccount(onSuccess: finish)
        case .antigravity:
            model.addAntigravityAccount(onSuccess: finish)
        case .copilot:
            model.addCopilotAccount(onSuccess: finish)
        case nil: break
        }
    }

    private func providerSubtitle(_ provider: LLMProvider) -> String {
        switch provider {
        case .codex: "Codex CLI"
        case .claude: "Claude Code"
        case .cursor: "Cursor Agent CLI"
        case .antigravity: "Antigravity CLI"
        case .copilot: "GitHub Copilot CLI"
        }
    }

    private func finish() {
        guard let selectedProvider else { return }
        Task {
            await model.completeOnboarding(with: selectedProvider)
            onComplete()
        }
    }

    private var appIcon: NSImage {
        guard let url = Bundle.main.url(forResource: "llm-account-switcher-icon", withExtension: "icns"),
              let image = NSImage(contentsOf: url) else {
            return NSApp.applicationIconImage
        }
        return image
    }
}
