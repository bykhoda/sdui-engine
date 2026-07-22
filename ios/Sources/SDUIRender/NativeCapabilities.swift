#if os(iOS)
import UIKit
import SwiftUI
import SDUICore
import SDUIRuntime
import AVFoundation
import CoreLocation
import UserNotifications
import Photos
import Contacts
import EventKit
import AppTrackingTransparency

// MARK: - Top-most view controller

/// Shared helper: the currently front-most presented controller, used to present
/// the version gate and the priming sheet over whatever is on screen.
@MainActor
enum SDUINativeTopVC {
    static func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        let key = windows.first(where: { $0.isKeyWindow }) ?? windows.first
        var top = key?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

// MARK: - Force-update gate

/// Presents the server-driven version gate as a `UIAlertController`. For a hard
/// gate (`dismissible == false`) the confirm action opens the App Store and then
/// **re-presents the same alert**, so the user cannot escape by any means but
/// updating. A soft gate adds a secondary "Later" button that simply dismisses.
///
/// No entitlements: the App Store id is contract data, and opening the Store is a
/// plain `UIApplication.open`.
@MainActor
final class SDUIVersionGate {
    static let shared = SDUIVersionGate()

    func present(alert: VersionAlert, storeURL: String) {
        guard let top = SDUINativeTopVC.topViewController() else { return }
        // Avoid stacking duplicate gates if `requireVersion` fires more than once.
        if top is UIAlertController { return }

        let controller = UIAlertController(title: alert.title,
                                           message: alert.message.isEmpty ? nil : alert.message,
                                           preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: alert.confirmTitle, style: .default) { [weak self] _ in
            self?.openStore(storeURL)
            // Hard gate: re-present so there is no way out but updating.
            if !alert.dismissible {
                // A small hop after the App Store hand-off so the re-present lands
                // on a clean presentation stack.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.present(alert: alert, storeURL: storeURL)
                }
            }
        })
        if alert.dismissible {
            controller.addAction(UIAlertAction(title: "Later", style: .cancel))
        }
        top.present(controller, animated: true)
    }

    private func openStore(_ storeURL: String) {
        guard let url = URL(string: storeURL) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Permission priming sheet

/// Renders the contract-authored `priming` subtree through the SDUI registry and
/// presents it as a sheet. Resolves `true` when the user confirms and `false`
/// when they cancel — so the interpreter can decide whether to burn the one-shot
/// system prompt. The subtree inherits the app's theme and press feel.
@MainActor
final class SDUIPermissionPriming {
    static let shared = SDUIPermissionPriming()

    private var selfRetain: SDUIPermissionPriming?

    func present(priming: PermissionPriming, registry: ComponentRegistry, ctx: RenderContext) async -> Bool {
        guard let top = SDUINativeTopVC.topViewController() else { return false }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            var didResume = false
            let finish: (Bool) -> Void = { confirmed in
                guard !didResume else { return }
                didResume = true
                self.selfRetain = nil
                continuation.resume(returning: confirmed)
            }

            let view = SDUIPrimingSheet(priming: priming, registry: registry, ctx: ctx,
                                        onConfirm: { finish(true) },
                                        onCancel: { finish(false) })
            let hosting = UIHostingController(rootView: view)
            hosting.modalPresentationStyle = .automatic
            // A swipe-to-dismiss counts as declining, so the promise always resolves.
            let proxy = SDUIPrimingDismissProxy { finish(false) }
            hosting.presentationController?.delegate = proxy
            self.selfRetain = self
            top.present(hosting, animated: true)
        }
    }
}

/// Bridges a swipe-to-dismiss of the priming sheet to the cancel path. Retains
/// itself until the sheet is dismissed so the delegate stays alive.
final class SDUIPrimingDismissProxy: NSObject, UIAdaptivePresentationControllerDelegate {
    private let onDismiss: () -> Void
    private var retain: SDUIPrimingDismissProxy?

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        super.init()
        self.retain = self
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onDismiss()
        retain = nil
    }
}

/// The priming sheet's SwiftUI body: the contract subtree (rendered via the same
/// registry as the screen) plus a confirm and a cancel button whose titles come
/// from the `priming` payload.
struct SDUIPrimingSheet: View {
    let priming: PermissionPriming
    let registry: ComponentRegistry
    let ctx: RenderContext
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var title: String { priming.raw["title"]?.stringValue ?? "" }
    private var message: String { priming.raw["message"]?.stringValue ?? "" }
    private var image: String? { priming.raw["image"]?.stringValue }
    private var confirmTitle: String { priming.raw["confirmTitle"]?.stringValue ?? "Continue" }
    private var cancelTitle: String { priming.raw["cancelTitle"]?.stringValue ?? "Not now" }

    var body: some View {
        VStack(spacing: 20) {
            // If the contract authored a full `component` subtree, render it as-is;
            // otherwise compose a default rationale layout from the priming fields.
            if let componentRaw = priming.raw["component"],
               let component = componentRaw.decode(Component.self) {
                registry.view(for: component, in: ctx)
            } else {
                if let image, !image.isEmpty {
                    Image(systemName: image)
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                        .padding(.top, 8)
                }
                if !title.isEmpty {
                    Text(title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                }
                if !message.isEmpty {
                    Text(message)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button(action: { dismiss(); onConfirm() }) {
                    Text(confirmTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Button(action: { dismiss(); onCancel() }) {
                    Text(cancelTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundColor(.accentColor)
                }
            }
        }
        .padding(24)
    }
}

// MARK: - Permission requests

/// Maps a neutral `PermissionRequest` onto the concrete OS framework, each behind
/// its own `#available` gate where iOS renamed the API. Below a needed iOS the
/// call is a clean no-op returning `.unavailable`, leaving `$state` well-defined.
///
/// Info.plist usage strings are host-app responsibility (see `requestPermission`).
@MainActor
enum SDUIPermissions {
    static func request(_ req: PermissionRequest) async -> PermissionOutcome {
        switch req.permission {
        case .camera:
            return await avCapture(.video)
        case .microphone:
            return await avCapture(.audio)
        case .location:
            return await SDUILocationAuth.shared.request(always: req.level == "always")
        case .notifications:
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            return granted ? .granted : .denied
        case .photos:
            let level: PHAccessLevel = (req.level == "addOnly") ? .addOnly : .readWrite
            let status = await PHPhotoLibrary.requestAuthorization(for: level)
            return mapPhotos(status)
        case .contacts:
            let store = CNContactStore()
            let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                store.requestAccess(for: .contacts) { granted, _ in cont.resume(returning: granted) }
            }
            return granted ? .granted : .denied
        case .calendar:
            return await requestCalendar()
        case .tracking:
            let status = await ATTrackingManager.requestTrackingAuthorization()
            switch status {
            case .authorized:     return .granted
            case .denied:         return .denied
            case .restricted:     return .restricted
            case .notDetermined:  return .notDetermined
            @unknown default:     return .denied
            }
        }
    }

    private static func avCapture(_ type: AVMediaType) async -> PermissionOutcome {
        let ok = await AVCaptureDevice.requestAccess(for: type)
        return ok ? .granted : .denied
    }

    private static func mapPhotos(_ status: PHAuthorizationStatus) -> PermissionOutcome {
        switch status {
        case .authorized, .limited: return .granted
        case .denied:               return .denied
        case .restricted:           return .restricted
        case .notDetermined:        return .notDetermined
        @unknown default:           return .denied
        }
    }

    private static func requestCalendar() async -> PermissionOutcome {
        let store = EKEventStore()
        if #available(iOS 17.0, *) {
            let ok = (try? await store.requestFullAccessToEvents()) ?? false
            return ok ? .granted : .denied
        } else {
            let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                store.requestAccess(to: .event) { granted, _ in cont.resume(returning: granted) }
            }
            return ok ? .granted : .denied
        }
    }
}

/// Wraps the delegate-callback `CLLocationManager` authorization into a single
/// `async` request. Retains itself for the duration of the (one-shot) callback.
@MainActor
final class SDUILocationAuth: NSObject, CLLocationManagerDelegate {
    static let shared = SDUILocationAuth()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<PermissionOutcome, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    func request(always: Bool) async -> PermissionOutcome {
        // If already decided, return the current status without re-prompting.
        let current = manager.authorizationStatus
        if current != .notDetermined { return Self.map(current) }

        return await withCheckedContinuation { (cont: CheckedContinuation<PermissionOutcome, Never>) in
            self.continuation = cont
            if always {
                manager.requestAlwaysAuthorization()
            } else {
                manager.requestWhenInUseAuthorization()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined, let cont = self.continuation else { return }
            self.continuation = nil
            cont.resume(returning: Self.map(status))
        }
    }

    private static func map(_ status: CLAuthorizationStatus) -> PermissionOutcome {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        case .denied:                                 return .denied
        case .restricted:                             return .restricted
        case .notDetermined:                          return .notDetermined
        @unknown default:                             return .denied
        }
    }
}
#endif
