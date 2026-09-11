import AppKit
import SwiftUI

/// A menu-bar panel positioned by hand.
///
/// `NSPopover` clamps itself to just under the menu bar and pushes ~2pt into it
/// no matter what anchor rect it's given — measured across every inset from -6
/// to +10, the top never moved below y=926 on a 924pt menu bar edge. Owning the
/// window outright is the only way to get an exact, predictable gap.
final class PanelController {

    /// Distance between the bottom of the menu bar and the top of the panel.
    static let gap: CGFloat = 6

    /// Minimum distance to keep from the left and right screen edges.
    private static let screenMargin: CGFloat = 8

    private let panel: NSPanel
    private let hosting: NSHostingController<ContentView>

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    var isVisible: Bool { panel.isVisible }

    init(state: AppState) {
        hosting = NSHostingController(rootView: ContentView(state: state))

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 312, height: 300),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // The glass cards sample what's behind the window, so the panel needs a
        // material of its own for the space between them to read as one surface.
        let backdrop = NSVisualEffectView()
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 18
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.masksToBounds = true

        hosting.view.autoresizingMask = [.width, .height]
        backdrop.addSubview(hosting.view)
        panel.contentView = backdrop

        // Pay SwiftUI's first layout now, not on the first click.
        hosting.view.layoutSubtreeIfNeeded()
    }

    // MARK: - Showing

    func toggle(from button: NSStatusBarButton) {
        isVisible ? close() : show(from: button)
    }

    func show(from button: NSStatusBarButton) {
        guard let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main
        else { return }

        let size = fittingSize()
        let icon = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))

        // visibleFrame already excludes the menu bar, notch inset included, so
        // this is the menu bar's bottom edge on notched and plain displays alike.
        let menuBarBottom = screen.visibleFrame.maxY

        var x = icon.midX - size.width / 2
        x = min(max(x, screen.frame.minX + Self.screenMargin),
                screen.frame.maxX - size.width - Self.screenMargin)

        let frame = NSRect(x: x, y: menuBarBottom - Self.gap - size.height,
                           width: size.width, height: size.height)

        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        NSApp.activate(ignoringOtherApps: true)

        startMonitoring()
    }

    func close() {
        stopMonitoring()
        panel.orderOut(nil)
    }

    /// Keeps the panel sized to its content when a card appears or disappears.
    func updateSizeIfVisible() {
        guard isVisible else { return }
        let size = fittingSize()
        guard size.height != panel.frame.height || size.width != panel.frame.width else { return }
        let top = panel.frame.maxY
        panel.setFrame(
            NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height),
            display: true
        )
        panel.invalidateShadow()
    }

    private func fittingSize() -> NSSize {
        hosting.view.layoutSubtreeIfNeeded()
        return hosting.view.fittingSize
    }

    // MARK: - Dismissal

    private func startMonitoring() {
        stopMonitoring()

        // Clicks in other apps. Clicks inside our own panel never reach this.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in self?.close()
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // Escape
            self?.close()
            return nil
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.close()
        }
    }

    private func stopMonitoring() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        globalMonitor = nil
        localMonitor = nil
        resignObserver = nil
    }
}
