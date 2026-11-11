import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case russian = "ru"
    case english = "en"

    var id: Self { self }
    var label: String { self == .russian ? "Русский" : "English" }
    var locale: Locale { Locale(identifier: rawValue) }

    static let initial: AppLanguage = {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") == true ? .russian : .english
    }()

    private static let bundles = Dictionary(uniqueKeysWithValues: allCases.compactMap { language in
        Bundle.main.path(forResource: language.rawValue, ofType: "lproj")
            .flatMap(Bundle.init(path:)).map { (language, $0) }
    })

    func text(_ key: TextKey, _ arguments: CVarArg...) -> String {
        let template = Self.bundles[self]?.localizedString(forKey: key.rawValue, value: nil, table: nil) ?? key.rawValue
        return arguments.isEmpty ? template : String(format: template, locale: locale, arguments: arguments)
    }

    func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file, spellsOutZero: false).locale(locale))
    }

    func count(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    func date(_ value: Date) -> String {
        value.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }

    func timestamp(_ value: Date) -> String {
        value.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))
    }
}

enum TextKey: String, CaseIterable {
    case appName, overview, files, settings, diskMenu, diskTitle
    case internalDisk, total, used, free, capacityUnavailable
    case scan, scanAgain, stop, scanning, stopping, inspected, scanCancelled, completed
    case topFolders, folderNote, ready, readyDetail, noFolders, partial, partialDetail, skippedTitle
    case skippedMore, permissionsHelp, systemSettings, done, stale
    case fileTitle, large, old, largeHint, oldHint, personalOnly, personalHelp
    case filename, size, modified, location, protectedFile, showFinder, moveToTrash
    case filesEmptyTitle, filesEmptyDetail, noMatches, noMatchesDetail, matchCount, cappedCount
    case selectedSize, viewOnlySelection, reviewTitle, reviewCount, reviewDetail, cancel, openTrash
    case moving, trashResult, trashMoved, trashSkipped, changed, protected, unavailable
    case trashUnavailable, appearance, language, systemTheme, lightTheme, darkTheme
}

private struct DiskLanguageKey: EnvironmentKey {
    static let defaultValue = AppLanguage.initial
}

extension EnvironmentValues {
    var diskLanguage: AppLanguage {
        get { self[DiskLanguageKey.self] }
        set { self[DiskLanguageKey.self] = newValue }
    }
}
