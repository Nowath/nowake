import SwiftUI

struct ContentView: View {

    @ObservedObject var state: AppState

    var body: some View {
        // One container so the glass layers sample a shared backdrop and blend
        // where they sit close together, rather than stacking independently.
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                header
                toggleCard
                if let message = state.warning.message { warningCard(message) }
                settingsCard
                statusCard
                passwordlessCard
                footer
            }
            .padding(12)
        }
        .frame(width: 312)
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
        .padding(.horizontal, 4)
    }

    // MARK: - The switch

    private var toggleCard: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(state.isActive ? Color.accentColor : Color.secondary.opacity(0.18))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(state.isActive ? Color.white : Color.secondary)
                }

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
        .glassCard(tint: state.isActive ? Color.accentColor.opacity(0.26) : nil)
        .animation(.easeInOut(duration: 0.2), value: state.isActive)
    }

    // MARK: - Warning

    private func warningCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text(message)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.orange)
        .glassCard(tint: Color.orange.opacity(0.24))
    }

    // MARK: - Settings

    private var settingsCard: some View {
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
        .glassCard()
    }

    // MARK: - Status

    private var statusCard: some View {
        VStack(spacing: 8) {
            statusRow(
                symbol: state.isLidClosed ? "laptopcomputer.slash" : "laptopcomputer",
                label: "Lid",
                value: state.isLidClosed ? "Closed" : "Open"
            )
            statusRow(symbol: state.power.symbolName, label: "Power", value: state.power.summary)
        }
        .glassCard()
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

    // MARK: - Passwordless turn-off

    private var passwordlessCard: some View {
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
        .glassCard()
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
        .padding(.horizontal, 4)
    }
}

// MARK: - Glass card

private struct GlassCard: ViewModifier {
    var tint: Color?

    func body(content: Content) -> some View {
        let glass: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
        return content
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(glass, in: .rect(cornerRadius: 14))
    }
}

private extension View {
    func glassCard(tint: Color? = nil) -> some View { modifier(GlassCard(tint: tint)) }
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
