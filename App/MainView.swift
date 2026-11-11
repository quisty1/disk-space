import AppKit
import SwiftUI

enum DiskPage: String, CaseIterable, Identifiable {
    case overview, files

    var id: Self { self }
    var title: TextKey { self == .overview ? .overview : .files }
    var icon: String { self == .overview ? "internaldrive" : "doc.on.doc" }
}

struct MainView: View {
    let model: AppModel
    @Environment(\.diskLanguage) private var language
    @State private var selection: DiskPage? = .overview

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                List(DiskPage.allCases, selection: $selection) { page in
                    Label(language.text(page.title), systemImage: page.icon)
                        .tag(page)
                }
                .listStyle(.sidebar)

                SettingsLink {
                    Label(language.text(.settings), systemImage: "gear")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 17)
                .padding(.vertical, 14)
            }
            .navigationSplitViewColumnWidth(min: 168, ideal: 192, max: 236)
        } detail: {
            Group {
                switch selection ?? .overview {
                case .overview:
                    OverviewView(model: model) { selection = .files }
                case .files:
                    FilesView(model: model)
                }
            }
            .navigationTitle(language.text((selection ?? .overview).title))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if model.isScanning {
                        Button {
                            model.cancelScan()
                        } label: {
                            Label(language.text(.stop), systemImage: "stop.circle")
                        }
                        .disabled(model.isCancelling)
                    } else {
                        Button {
                            model.startScan()
                        } label: {
                            Label(language.text(model.results == nil ? .scan : .scanAgain),
                                  systemImage: "arrow.clockwise")
                        }
                        .disabled(model.isMoving)
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.isScanning {
                    ScanStatusView(progress: model.progress, isCancelling: model.isCancelling)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct ScanStatusView: View {
    let progress: ScanProgress?
    let isCancelling: Bool
    @Environment(\.diskLanguage) private var language

    var body: some View {
        HStack(spacing: 11) {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(language.text(isCancelling ? .stopping : .scanning))
                    .font(.callout.weight(.semibold))
                if let progress {
                    Text(progress.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(progress.path)
                }
            }
            Spacer(minLength: 12)
            if let progress {
                Text(language.text(.inspected, language.count(progress.inspectedCount)))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 9)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct DiskCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.60), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func diskCard() -> some View { modifier(DiskCard()) }
}

struct DiskEmptyView: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 365)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 23)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }
}
