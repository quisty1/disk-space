import AppKit
import SwiftUI

@main
struct DiskSpaceApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window(model.language.text(.appName), id: "disk-space") {
            MainView(model: model)
                .environment(\.diskLanguage, model.language)
                .environment(\.locale, model.language.locale)
                .frame(minWidth: 815, minHeight: 560)
                .onAppear { model.applyTheme() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.refreshCapacity()
                }
        }
        .defaultSize(width: 1040, height: 700)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink { Text(model.language.text(.settings)) }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu(model.language.text(.diskMenu)) {
                Button(model.language.text(.scan)) { model.startScan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isScanning || model.isMoving)
                Button(model.language.text(.stop)) { model.cancelScan() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.isScanning || model.isCancelling)
            }
        }

        Settings {
            PreferencesView(model: model)
                .environment(\.diskLanguage, model.language)
                .environment(\.locale, model.language.locale)
        }
    }
}

private struct PreferencesView: View {
    @Bindable var model: AppModel
    @Environment(\.diskLanguage) private var language

    var body: some View {
        Form {
            Picker(language.text(.appearance), selection: $model.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(language.text(theme.title)).tag(theme)
                }
            }
            Picker(language.text(.language), selection: $model.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.label).tag(language)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 425, height: 155)
        .background {
            SettingsWindowTitle(title: language.text(.settings))
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

private struct SettingsWindowTitle: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> TitleView { TitleView() }

    func updateNSView(_ view: TitleView, context: Context) {
        view.title = title
    }

    final class TitleView: NSView {
        var title = "" {
            didSet { window?.title = title }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.title = title
        }
    }
}
