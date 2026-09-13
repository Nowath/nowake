import SwiftUI

struct ContentView: View {

    @ObservedObject var state: AppState

    var body: some View {
        // The panel is one pane of Liquid Glass. Everything inside it is the
        // content layer — grouped by a faint scrim, not by more glass — so the
        // only things that float above the surface are the controls.
        VStack(alignment: .leading, spacing: 0) {
                header
                separator
                toggleRow
                if let message = state.warning.message {
                    warningRow(message)
                        .transition(.opacity)
                }
                separator
                settingsGroup
                separator
                statusGroup
                separator
                if state.touchIDAvailable {
                    touchIDRow
                    separator
                }
                passwordlessRow
                separator
                footer
            }
        .frame(width: 312)
        .animation(.smooth(duration: 0.22), value: state.warning.message)
    }

    /// Full-bleed, like the hairlines in a system menu. `separatorColor` rather
    /// than a hand-picked opacity, so it tracks the material in both themes.
    private var separator: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 0.5)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            Text("nowake")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(state.isActive ? Color.green : Color.secondary.opacity(0.45))
                    .frame(width: 7, height: 7)
                Text(state.isActive ? "Active" : "Off")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - The switch

    /// The icon tile is the one piece of glass that sits *on* the pane: it's a
    /// control, so it belongs to the layer above the content, and `.interactive()`
    /// gives it the press response that comes with that.
    private var toggleRow: some View {
        HStack(spacing: 11) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(state.isActive ? Color.white : Color.secondary)
                .frame(width: 32, height: 32)
                .background(
                    state.isActive ? Color.accentColor : Color.primary.opacity(0.10),
                    in: .rect(cornerRadius: 9, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Keep awake")
                    .font(.system(size: 13, weight: .medium))
                ElapsedLabel(ticker: state.ticker)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(get: { state.isActive }, set: { _ in state.requestToggle() }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .contentGroup(tint: state.isActive ? Color.accentColor : nil)
        .animation(.easeInOut(duration: 0.2), value: state.isActive)
    }

    // MARK: - Warning

    private func warningRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text(message)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.orange)
        .contentGroup(tint: Color.orange)
    }

    // MARK: - Settings

    private var settingsGroup: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Text("Auto-off")
                    .font(.system(size: 12))
                    .foregroundStyle(state.isActive ? Color.primary : Color.secondary)
                RemainingLabel(ticker: state.ticker)
                Spacer(minLength: 4)
                Picker("", selection: $state.autoOff) {
                    ForEach(AutoOff.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 112, alignment: .trailing)
                .disabled(!state.isActive)
            }

            HStack(spacing: 8) {
                Text("Turn off below")
                    .font(.system(size: 12))
                    .foregroundStyle(state.isActive ? Color.primary : Color.secondary)
                Spacer(minLength: 4)
                Picker("", selection: $state.batteryLimit) {
                    ForEach(BatteryLimit.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 112, alignment: .trailing)
                .disabled(!state.isActive || !state.power.hasBattery)
            }
        }
        .contentGroup()
    }

    // MARK: - Status

    private var statusGroup: some View {
        VStack(spacing: 8) {
            statusRow(
                symbol: state.isLidClosed ? "laptopcomputer.slash" : "laptopcomputer",
                label: "Lid",
                value: state.isLidClosed ? "Closed" : "Open"
            )
            statusRow(symbol: state.power.symbolName, label: "Power", value: state.power.summary)
        }
        .contentGroup()
    }

    private func statusRow(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
        }
    }

    // MARK: - Touch ID

    private var touchIDRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "touchid")
                .font(.system(size: 12))
                .foregroundStyle(state.touchIDEnabled ? Color.pink : Color.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text("Unlock with Touch ID")
                    .font(.system(size: 12))
                Text(state.touchIDEnabled ? "Authorize with your fingerprint"
                                          : "Asks you to type your password")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { state.touchIDEnabled },
                set: { state.setTouchID($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .contentGroup()
    }

    // MARK: - Passwordless turn-off

    private var passwordlessRow: some View {
        HStack(spacing: 10) {
            Image(systemName: state.passwordlessOff ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text("Turn off without password")
                    .font(.system(size: 12))
                Text(state.passwordlessOff ? "Timer and cutoff can fire unattended"
                                           : "Asks for your password to turn off")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { state.passwordlessOff },
                set: { state.setPasswordlessOff($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .contentGroup()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("v1.0")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { state.quit() }
                .buttonStyle(.glass)
                .controlSize(.small)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Content group

/// A grouped row on the glass pane. Deliberately *not* glass — stacking glass
/// inside glass cancels out the refraction and leaves both layers looking flat.
/// A faint scrim in the pane's own colour is enough to read as a group.
private struct ContentGroup: ViewModifier {
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Full-bleed like the highlighted block in a Focus menu — a rounded
            // card here would put a second container inside the pane.
            .background((tint ?? Color.clear).opacity(tint == nil ? 0 : 0.18))
    }
}

private extension View {
    func contentGroup(tint: Color? = nil) -> some View { modifier(ContentGroup(tint: tint)) }
}

// MARK: - Per-second labels

/// These observe `Ticker`, not `AppState`, so the once-a-second update redraws
/// two `Text` views instead of the entire panel.
private struct ElapsedLabel: View {
    @ObservedObject var ticker: Ticker

    var body: some View {
        Text(ticker.elapsed ?? "with the lid closed")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}

private struct RemainingLabel: View {
    @ObservedObject var ticker: Ticker

    var body: some View {
        if let remaining = ticker.remaining {
            Text(remaining)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
