import SwiftUI
import AppKit
import ApplicationServices

// MARK: - SettingsWindowController

class SettingsWindowController: NSWindowController {
    static let shared: SettingsWindowController = {
        let appState = AppState.shared
        let rootView = SettingsView()
            .environmentObject(appState)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Monkey Flash"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 480, height: 420))
        window.isReleasedWhenClosed = false
        return SettingsWindowController(window: window)
    }()

    func open() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }
            VisualTab()
                .tabItem { Label("Visual", systemImage: "paintbrush") }
            ShortcutsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .padding(8)
        .frame(minWidth: 460, minHeight: 380)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Enable Highlight", isOn: $appState.isEnabled)
                Toggle("Show Status Bar Icon", isOn: $appState.showStatusBarIcon)
            }

            Section {
                Button("Request Accessibility Permission") {
                    AXIsProcessTrustedWithOptions(
                        [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    )
                }
            }

            Section {
                Button("Quit Monkey Flash") {
                    NSApp.terminate(nil)
                }
                .foregroundColor(.red)
            }
        }
        .padding()
    }
}

// MARK: - Visual Tab

struct VisualTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section(header: Text("Dimming")) {
                HStack {
                    Text("Opacity")
                    Slider(value: $appState.dimOpacity, in: 0.15...0.9, step: 0.05)
                    Text("\(Int(appState.dimOpacity * 100))%")
                        .frame(width: 40, alignment: .trailing)
                        .monospacedDigit()
                }
            }

            Section(header: Text("Blur")) {
                Toggle("Enable Blur", isOn: $appState.isBlurEnabled)

                if appState.isBlurEnabled {
                    HStack {
                        Text("Intensity")
                        Slider(value: $appState.blurIntensity, in: 0.1...1.0, step: 0.05)
                        Text("\(Int(appState.blurIntensity * 100))%")
                            .frame(width: 40, alignment: .trailing)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Shortcuts Tab

struct ShortcutsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Click a shortcut field to record. Press Esc to cancel, Delete to clear.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(HotkeyAction.allCases, id: \.rawValue) { action in
                        ShortcutRow(action: action)
                        Divider().padding(.leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ShortcutRow: View {
    let action: HotkeyAction
    @EnvironmentObject var appState: AppState

    var currentCombo: HotkeyCombo? {
        appState.shortcuts[action.rawValue]
    }

    var body: some View {
        HStack {
            Text(action.displayName)
                .frame(maxWidth: .infinity, alignment: .leading)
            ShortcutRecorderView(
                combo: currentCombo,
                onChange: { newCombo in
                    if let newCombo {
                        appState.shortcuts[action.rawValue] = newCombo
                    } else {
                        appState.shortcuts.removeValue(forKey: action.rawValue)
                    }
                }
            )
            .frame(width: 140, height: 24)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}

// MARK: - ShortcutRecorderView (NSViewRepresentable)

struct ShortcutRecorderView: NSViewRepresentable {
    var combo: HotkeyCombo?
    var onChange: (HotkeyCombo?) -> Void

    func makeNSView(context: Context) -> ShortcutButton {
        let button = ShortcutButton()
        button.coordinator = context.coordinator
        return button
    }

    func updateNSView(_ nsView: ShortcutButton, context: Context) {
        context.coordinator.onChange = onChange
        if !nsView.isRecording {
            nsView.combo = combo
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    final class Coordinator {
        var onChange: (HotkeyCombo?) -> Void
        init(onChange: @escaping (HotkeyCombo?) -> Void) { self.onChange = onChange }
    }
}

// MARK: - ShortcutButton

final class ShortcutButton: NSButton {
    var combo: HotkeyCombo? { didSet { if !isRecording { updateTitle() } } }
    var coordinator: ShortcutRecorderView.Coordinator?
    private(set) var isRecording = false
    private var eventMonitor: Any?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        bezelStyle = .rounded
        font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        target = self
        action = #selector(buttonClicked)
        updateTitle()
    }

    private func updateTitle() {
        if isRecording {
            title = "Recording…"
        } else if let combo {
            title = combo.displayString
        } else {
            title = "—"
        }
    }

    @objc private func buttonClicked() {
        guard !isRecording else { return }
        startRecording()
    }

    private func startRecording() {
        isRecording = true
        updateTitle()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        if event.keyCode == 53 {
            // Escape — cancel, keep existing combo
            stopRecording(with: combo)
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            // Delete / Forward-delete — clear the shortcut
            stopRecording(with: nil)
            return
        }

        // Ignore bare modifier-only presses
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let newCombo = HotkeyCombo(keyCode: event.keyCode, modifiers: flags.rawValue)
        stopRecording(with: newCombo)
    }

    private func stopRecording(with newCombo: HotkeyCombo?) {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        combo = newCombo
        updateTitle()
        coordinator?.onChange(newCombo)
    }

    deinit {
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
    }
}
