import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var panel: PanelController!
    private let state = AppState()

    private var renderedIcon: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.target = self

        panel = PanelController(state: state)

        state.onStateChange = { [weak self] in
            self?.updateStatusItem()
            self?.panel.updateSizeIfVisible()
        }
        state.start()
        updateStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SleepBlocker.releaseAssertion()
    }

    // MARK: - Menu bar item

    private func updateStatusItem() {
        let symbol: String
        let tooltip: String

        switch (state.isActive, state.isLidClosed, state.warning) {
        case (true, _, .critical), (true, _, .low):
            symbol = "exclamationmark.triangle.fill"
            tooltip = "nowake — active, battery low"
        case (true, true, _):
            symbol = "laptopcomputer.slash"
            tooltip = "nowake — awake with the lid closed"
        case (true, false, _):
            symbol = "cup.and.saucer.fill"
            tooltip = "nowake — active"
        case (false, _, _):
            symbol = "cup.and.saucer"
            tooltip = "nowake — off"
        }

        // The 1 Hz tick would otherwise rebuild this image every second.
        guard renderedIcon != symbol else {
            statusItem.button?.toolTip = tooltip
            return
        }
        renderedIcon = symbol

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = tooltip
    }

    // MARK: - Panel

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if panel.isVisible {
            panel.close()
            return
        }
        state.refresh()
        state.refreshPrivilegeStatus()   // async; never blocks the click
        panel.show(from: button)
    }
}
