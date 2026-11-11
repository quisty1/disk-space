import AppKit
import SwiftUI

struct OverviewView: View {
    let model: AppModel
    let showFiles: () -> Void
    @Environment(\.diskLanguage) private var language
    @State private var showingPermissions = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(language.text(.diskTitle))
                    .font(.system(size: 34, weight: .bold))
                    .accessibilityAddTraits(.isHeader)

                CapacityCard(capacity: model.capacity)

                if model.wasCancelled {
                    Label(language.text(.scanCancelled), systemImage: "stop.circle")
                        .foregroundStyle(.secondary)
                }

                if let result = model.results {
                    if result.skippedCount > 0 {
                        Button {
                            showingPermissions = true
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                                Text(language.text(.partial, language.count(result.skippedCount)))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .diskCard()
                        .sheet(isPresented: $showingPermissions) {
                            ScanPermissionsView(result: result)
                        }
                    }

                    folders(result)

                    HStack(alignment: .firstTextBaseline) {
                        Text(language.text(.completed, language.timestamp(result.completedAt)))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !model.removedPaths.isEmpty {
                            Text(language.text(.stale)).foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                } else if !model.isScanning {
                    readyCard
                }
            }
            .frame(maxWidth: 1020, alignment: .leading)
            .padding(.horizontal, 25)
            .padding(.top, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var readyCard: some View {
        VStack(spacing: 0) {
            DiskEmptyView(icon: "magnifyingglass", title: language.text(.ready), detail: language.text(.readyDetail))
            Button {
                model.startScan()
            } label: {
                Label(language.text(.scan), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isScanning || model.isMoving)
            .padding(.bottom, 23)
        }
        .diskCard()
    }

    private func folders(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language.text(.topFolders)).font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: showFiles) {
                    Text(language.text(.files))
                }
                .buttonStyle(.link)
            }

            if result.folders.isEmpty {
                Text(language.text(.noFolders))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .diskCard()
            } else {
                let largest = result.folders.first?.allocatedBytes ?? 1
                VStack(spacing: 0) {
                    ForEach(result.folders) { folder in
                        if folder.id != result.folders.first?.id { Divider().padding(.leading, 42) }
                        folderRow(folder, largest: largest)
                    }
                }
                .diskCard()
                Text(language.text(.folderNote)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func folderRow(_ folder: FolderUsage, largest: Int64) -> some View {
        HStack(spacing: 10) {
            Image(systemName: folder.path == "/" ? "internaldrive" : "folder")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name).lineLimit(1)
                Text(folder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            GeometryReader { proxy in
                let ratio = Double(folder.allocatedBytes) / Double(largest)
                Capsule().fill(Color.accentColor.opacity(0.14))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.accentColor.opacity(0.70))
                            .frame(width: max(2, proxy.size.width * ratio))
                    }
            }
            .frame(width: 78, height: 4)
            .accessibilityHidden(true)
            Text(language.bytes(folder.allocatedBytes))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 86, alignment: .trailing)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct CapacityCard: View {
    let capacity: DiskCapacity?
    @Environment(\.diskLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(spacing: 13) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(capacity?.name ?? language.text(.internalDisk))
                        .font(.title3.weight(.semibold))
                    Text(capacity.map { language.text(.total, language.bytes($0.total)) }
                         ?? language.text(.capacityUnavailable))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let capacity {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.48))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Color.accentColor.gradient)
                                .frame(width: proxy.size.width * capacity.usedFraction)
                        }
                }
                .frame(height: 12)
                .accessibilityHidden(true)

                HStack(alignment: .top, spacing: 22) {
                    capacityValue(.used, bytes: capacity.used, color: .accentColor)
                    capacityValue(.free, bytes: capacity.free, color: Color(nsColor: .tertiaryLabelColor))
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .diskCard()
    }

    private func capacityValue(_ key: TextKey, bytes: Int64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
                Text(language.text(key)).font(.caption).foregroundStyle(.secondary)
            }
            Text(language.bytes(bytes))
                .font(.system(size: 23, weight: .semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ScanPermissionsView: View {
    let result: ScanResult
    @Environment(\.diskLanguage) private var language
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(language.text(.skippedTitle)).font(.title2.weight(.semibold))
            Text(language.text(.partialDetail)).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(result.skippedPaths.indices, id: \.self) { index in
                        Text(result.skippedPaths[index])
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .frame(height: 145)
            if result.skippedCount > result.skippedPaths.count {
                Text(language.text(.skippedMore, language.count(result.skippedCount - result.skippedPaths.count)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(language.text(.permissionsHelp))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(language.text(.systemSettings)) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                }
                Spacer()
                Button(language.text(.done)) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 530)
    }
}
