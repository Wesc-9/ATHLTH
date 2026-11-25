import SwiftUI
import LocalAuthentication
import UIKit

/// Device-local preference. Biometric data and device passcodes never leave iOS.
enum ATHLTHAppLock {
    static let preferenceKey = "athlth.security.appLockOwner.v1"

    @MainActor static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch { return false }
    }
}

/// A separate scene window covers presented sheets too, while leaving the
/// underlying SwiftUI navigation and active workout stores intact.
struct ATHLTHAppLockBridge: UIViewRepresentable {
    let owner: UUID?
    let enabled: Bool
    let phase: ScenePhase

    final class Anchor: UIView {
        var didAttach: ((UIWindowScene?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            didAttach?(window?.windowScene)
        }
    }

    @MainActor final class Coordinator {
        private weak var scene: UIWindowScene?
        private weak var previousKey: UIWindow?
        private var cover: UIWindow?
        private var owner: UUID?
        private var enabled = false
        private var phase: ScenePhase = .inactive
        private var locked = false
        private var authenticating = false
        private var failed = false
        private var generation = 0

        func attach(_ scene: UIWindowScene?) {
            guard self.scene !== scene else { return }
            hide()
            self.scene = scene
            render()
        }

        func update(owner: UUID?, enabled: Bool, phase: ScenePhase) {
            let changedOwner = self.owner != owner
            if changedOwner || self.enabled != enabled {
                generation += 1
                authenticating = false
                failed = false
                // Enabling from the settings is already authenticated. A
                // restored locked account must authenticate on a fresh launch.
                locked = enabled && (changedOwner || self.phase != .active)
            }
            self.owner = owner
            self.enabled = enabled && owner != nil
            self.phase = phase
            if self.enabled && phase == .background {
                if !locked || authenticating { generation += 1 }
                locked = true
                authenticating = false
                failed = false
            }
            if !self.enabled { locked = false }
            render()
        }

        private func render() {
            guard enabled, let scene, locked || phase != .active else {
                hide(); return
            }
            let interactive = locked && phase == .active
            let content = ATHLTHLockedScreen(
                interactive: interactive, authenticating: authenticating, failed: failed,
                unlock: { [weak self] in self?.unlock() }
            )
            if let cover {
                (cover.rootViewController as? UIHostingController<ATHLTHLockedScreen>)?.rootView = content
            } else {
                let window = UIWindow(windowScene: scene)
                window.windowLevel = .alert + 1
                window.rootViewController = UIHostingController(rootView: content)
                window.backgroundColor = .systemBackground
                previousKey = scene.windows.first(where: { $0.isKeyWindow })
                cover = window
                window.isHidden = false
            }
            if interactive && cover?.isKeyWindow == false { cover?.makeKeyAndVisible() }
        }

        private func hide() {
            let wasKey = cover?.isKeyWindow == true
            cover?.isHidden = true
            cover?.rootViewController = nil
            cover = nil
            if wasKey { previousKey?.makeKey() }
            previousKey = nil
        }

        private func unlock() {
            guard enabled, locked, phase == .active, !authenticating else { return }
            authenticating = true; failed = false
            let attempt = generation
            render()
            Task { @MainActor [weak self] in
                let accepted = await ATHLTHAppLock.authenticate(reason: ATHLTHLocalization.choose(
                    english: "Unlock ATHLTH", norwegian: "Lås opp ATHLTH"))
                guard let self, self.generation == attempt else { return }
                self.authenticating = false
                self.locked = !accepted
                self.failed = !accepted
                self.render()
            }
        }

        func dismantle() {
            generation += 1
            hide()
            scene = nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> Anchor {
        let view = Anchor()
        view.isUserInteractionEnabled = false
        view.didAttach = { [weak coordinator = context.coordinator] scene in
            coordinator?.attach(scene)
        }
        return view
    }
    func updateUIView(_ view: Anchor, context: Context) {
        context.coordinator.update(owner: owner, enabled: enabled, phase: phase)
        if let scene = view.window?.windowScene { context.coordinator.attach(scene) }
    }
    static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) {
        view.didAttach = nil
        coordinator.dismantle()
    }
}

private struct ATHLTHLockedScreen: View {
    let interactive: Bool
    let authenticating: Bool
    let failed: Bool
    let unlock: () -> Void

    var body: some View {
        ZStack {
            ATHLTHTheme.canvasTop.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                Text("ATHLTH").font(.system(size: 32, design: .serif))
                if interactive {
                    Text(ATHLTHLocalization.choose(english: "Your app is locked", norwegian: "Appen er låst"))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    Button(action: unlock) {
                        Label(ATHLTHLocalization.choose(english: "Unlock", norwegian: "Lås opp"),
                              systemImage: "faceid")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)
                    .disabled(authenticating)
                    if authenticating { ProgressView() }
                    if failed {
                        Text(ATHLTHLocalization.choose(
                            english: "Use Face ID, Touch ID or your device passcode. If unavailable, enable a device passcode in Settings and retry.",
                            norwegian: "Bruk Face ID, Touch ID eller enhetskoden. Hvis dette ikke er tilgjengelig, aktiver enhetskode i Innstillinger og prøv igjen."))
                            .font(.caption).multilineTextAlignment(.center)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                }
            }.padding(30)
        }
    }
}
