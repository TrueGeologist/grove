import SwiftUI

enum FileCategory: UInt8 {
    case folder
    case image
    case video
    case audio
    case archive
    case document
    case code
    case app
    case disk
    case other

    static func classify(name: String, isDirectory: Bool) -> FileCategory {
        let ext = (name as NSString).pathExtension.lowercased()
        if isDirectory {
            if ext == "app" || ext == "photoslibrary" || ext == "musiclibrary" { return .app }
            return .folder
        }
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tif", "tiff", "raw", "dng", "bmp", "svg", "icns":
            return .image
        case "mp4", "mov", "m4v", "mkv", "avi", "webm", "mpg", "mpeg":
            return .video
        case "mp3", "m4a", "aac", "wav", "aiff", "flac", "alac", "caf":
            return .audio
        case "dmg", "iso", "sparseimage", "sparsebundle":
            return .disk
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz":
            return .archive
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "rtf", "txt", "md", "csv":
            return .document
        case "swift", "m", "mm", "h", "c", "cpp", "hpp", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "java", "kt", "json", "xml", "html", "css", "sh", "zsh":
            return .code
        case "app":
            return .app
        default:
            return .other
        }
    }

    var symbol: String {
        switch self {
        case .folder: return "folder.fill"
        case .image: return "photo.fill"
        case .video: return "film.fill"
        case .audio: return "music.note"
        case .archive: return "archivebox.fill"
        case .document: return "doc.text.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .app: return "app.fill"
        case .disk: return "externaldrive.fill"
        case .other: return "doc.fill"
        }
    }

    func color(in scheme: ColorScheme) -> Color {
        let dark = scheme == .dark
        switch self {
        case .folder:
            return dark ? Color(white: 0.55) : Color(white: 0.35)
        case .image:
            return dark ? Color(red: 0.90, green: 0.48, blue: 0.40) : Color(red: 0.76, green: 0.36, blue: 0.29)
        case .video:
            return dark ? Color(red: 0.93, green: 0.62, blue: 0.32) : Color(red: 0.76, green: 0.46, blue: 0.18)
        case .audio:
            return dark ? Color(red: 0.66, green: 0.54, blue: 0.86) : Color(red: 0.45, green: 0.36, blue: 0.62)
        case .archive:
            return dark ? Color(red: 0.45, green: 0.64, blue: 0.84) : Color(red: 0.24, green: 0.42, blue: 0.58)
        case .document:
            return dark ? Color(red: 0.38, green: 0.72, blue: 0.66) : Color(red: 0.22, green: 0.48, blue: 0.45)
        case .code:
            return dark ? Color(red: 0.48, green: 0.74, blue: 0.50) : Color(red: 0.28, green: 0.48, blue: 0.32)
        case .app:
            return dark ? Color(red: 0.55, green: 0.60, blue: 0.90) : Color(red: 0.33, green: 0.37, blue: 0.62)
        case .disk:
            return dark ? Color(red: 0.86, green: 0.55, blue: 0.38) : Color(red: 0.64, green: 0.40, blue: 0.22)
        case .other:
            return dark ? Color(white: 0.62) : Color(white: 0.42)
        }
    }
}

enum GroveColor {
    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.105, green: 0.112, blue: 0.118)
            : Color(red: 0.945, green: 0.938, blue: 0.922)
    }

    static func folder(name: String, scheme: ColorScheme) -> Color {
        let hues: [Double] = [152, 188, 208, 26, 350, 262, 172, 128]
        let hue = hues[stableHash(name) % hues.count] / 360
        if scheme == .dark {
            return Color(hue: hue, saturation: 0.30, brightness: 0.36)
        }
        return Color(hue: hue, saturation: 0.24, brightness: 0.84)
    }

    static func tile(category: FileCategory, name: String, scheme: ColorScheme) -> Color {
        if category == .folder {
            return folder(name: name, scheme: scheme)
        }
        return category.color(in: scheme)
    }

    static func label(category: FileCategory, scheme: ColorScheme) -> Color {
        if category == .folder {
            return scheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.78)
        }
        return .white
    }

    static func secondaryLabel(category: FileCategory, scheme: ColorScheme) -> Color {
        label(category: category, scheme: scheme).opacity(0.78)
    }

    private static func stableHash(_ value: String) -> Int {
        var hash = 5381
        for byte in value.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
        return abs(hash)
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case ru
    case en

    var id: String { rawValue }
}

final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()
    private static let key = "grove.language"

    @Published var choice: AppLanguage {
        didSet { UserDefaults.standard.set(choice.rawValue, forKey: Self.key) }
    }

    var russian: Bool {
        switch choice {
        case .ru: return true
        case .en: return false
        case .system: return Locale.current.language.languageCode?.identifier == "ru"
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.key) ?? ""
        choice = AppLanguage(rawValue: stored) ?? .system
    }
}

enum Format {
    private static var russian: Bool { LanguageStore.shared.russian }

    private static var numberLocale: Locale {
        Locale(identifier: russian ? "ru" : "en")
    }

    static func bytes(_ value: Int64) -> String {
        let sign = value < 0 ? "−" : ""
        var amount = Double(abs(value))
        let units = russian ? ["Б", "КБ", "МБ", "ГБ", "ТБ"] : ["B", "KB", "MB", "GB", "TB"]
        var index = 0
        while amount >= 1000, index < units.count - 1 {
            amount /= 1000
            index += 1
        }
        if index == 0 {
            return "\(sign)\(Int(amount)) \(units[index])"
        }
        let digits = amount >= 10 ? 0 : 1
        let number = String(format: "%.\(digits)f", locale: numberLocale, amount)
        return "\(sign)\(number) \(units[index])"
    }

    static func share(_ part: Int64, of whole: Int64) -> String {
        guard whole > 0, part > 0 else { return "0%" }
        let ratio = Double(part) / Double(whole)
        if ratio < 0.001 { return russian ? "<0,1%" : "<0.1%" }
        if ratio < 0.1 {
            return String(format: "%.1f%%", locale: numberLocale, ratio * 100)
        }
        return String(format: "%.0f%%", locale: numberLocale, ratio * 100)
    }

    static func files(_ count: Int) -> String {
        plural(count, one: russian ? "файл" : "file", few: russian ? "файла" : "files", many: russian ? "файлов" : "files")
    }

    static func items(_ count: Int) -> String {
        plural(count, one: russian ? "элемент" : "item", few: russian ? "элемента" : "items", many: russian ? "элементов" : "items")
    }

    static func duration(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return String(format: "%.1f %@", locale: numberLocale, interval, russian ? "с" : "s")
        }
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if russian { return "\(minutes) мин \(seconds) с" }
        return "\(minutes)m \(seconds)s"
    }

    static func rate(_ filesPerSecond: Double) -> String {
        if filesPerSecond < 10 { return "" }
        let rounded = Int(filesPerSecond.rounded())
        let grouped = grouped(rounded)
        return russian ? "\(grouped)/с" : "\(grouped)/s"
    }

    static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = numberLocale
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func plural(_ count: Int, one: String, few: String, many: String) -> String {
        let number = grouped(count)
        if !russian { return "\(number) \(count == 1 ? one : many)" }
        let mod100 = abs(count) % 100
        let mod10 = abs(count) % 10
        let word: String
        if mod100 > 10 && mod100 < 20 {
            word = many
        } else if mod10 > 1 && mod10 < 5 {
            word = few
        } else if mod10 == 1 {
            word = one
        } else {
            word = many
        }
        return "\(number) \(word)"
    }
}

enum Copy {
    static var russian: Bool { LanguageStore.shared.russian }

    static var tagline: String { russian ? "Найдите, чем занято место" : "See what is using your disk" }
    static var home: String { russian ? "Домашняя папка" : "Home" }
    static var chooseFolder: String { russian ? "Выбрать папку…" : "Choose Folder…" }
    static var disks: String { russian ? "Диски" : "Disks" }
    static var recents: String { russian ? "Недавние" : "Recent" }
    static var largest: String { russian ? "Крупные" : "Largest" }
    static var matches: String { russian ? "Совпадения" : "Matches" }
    static var filterPrompt: String { russian ? "Имя файла или папки" : "File or folder name" }
    static var up: String { russian ? "Наверх" : "Up" }
    static var reveal: String { russian ? "В Finder" : "Show in Finder" }
    static var trash: String { russian ? "В Корзину" : "Move to Trash" }
    static var rescan: String { russian ? "Обновить" : "Rescan" }
    static var stop: String { russian ? "Остановить" : "Stop" }
    static var otherFolder: String { russian ? "Другая папка…" : "Another Folder…" }
    static var quickLook: String { russian ? "Быстрый просмотр" : "Quick Look" }
    static var openFolder: String { russian ? "Открыть папку" : "Open Folder" }
    static var copyPath: String { russian ? "Скопировать путь" : "Copy Path" }
    static var free: String { russian ? "свободно" : "free" }
    static var used: String { russian ? "занято" : "used" }
    static var ofCapacity: String { russian ? "из" : "of" }
    static var sharedCopies: String {
        russian
            ? "Плитки складывают размер файлов. Одинаковые копии на диске хранятся один раз, поэтому их сумма больше, чем занято в настройках."
            : "Tiles add up file sizes. Identical copies are stored once, so their sum can exceed the space used in Settings."
    }
    static var onDisk: String { russian ? "на диске" : "on disk" }
    static var remainder: String { russian ? "Остальное" : "Everything else" }
    static var scanning: String { russian ? "Сканирование" : "Scanning" }
    static var done: String { russian ? "Готово" : "Done" }
    static var stopped: String { russian ? "Остановлено" : "Stopped" }
    static var emptyFolder: String { russian ? "В этой папке пока ничего нет" : "This folder is empty so far" }
    static var noMatches: String { russian ? "Ничего не найдено" : "Nothing matches" }
    static var hint: String {
        russian
            ? "Щелчок выбирает. Двойной щелчок открывает папку. Пробел — быстрый просмотр."
            : "Click to select. Double-click a folder to open it. Space for Quick Look."
    }
    static var protectedTitle: String { russian ? "Эту папку нельзя удалить" : "This folder can’t be moved to the Trash" }
    static var protectedBody: String {
        russian
            ? "Grove не удаляет системные и домашние папки целиком."
            : "Grove won’t delete an entire system or home folder."
    }
    static var trashTitle: String { russian ? "Переместить в Корзину?" : "Move to the Trash?" }
    static var cancel: String { russian ? "Отмена" : "Cancel" }
    static var trashFailed: String { russian ? "Не удалось переместить в Корзину" : "Couldn’t move to the Trash" }
    static var accessTitle: String { russian ? "Часть папок недоступна" : "Some folders couldn’t be read" }
    static var accessBody: String {
        russian
            ? "Для полного обзора включите Grove в «Полный доступ к диску» и запустите обход ещё раз."
            : "Grant Grove Full Disk Access, then scan again."
    }
    static var systemSkip: String {
        russian
            ? "Несколько системных папок закрыты защитой macOS. На размер ваших файлов это почти не влияет."
            : "macOS keeps a few system folders unreadable. That barely affects your files."
    }
    static var accessButton: String { russian ? "Настройки" : "Settings" }
    static var otherDisk: String { russian ? "Другой диск" : "Another disk" }
    static var pathCopied: String { russian ? "Путь скопирован" : "Path copied" }
    static var continueMap: String { russian ? "Вернуться к карте" : "Back to the map" }
    static var freedNote: String { russian ? "Освободится около" : "About this much will be freed" }
    static var downloads: String { russian ? "Загрузки" : "Downloads" }
    static var documents: String { russian ? "Документы" : "Documents" }
    static var desktop: String { russian ? "Рабочий стол" : "Desktop" }
    static var settingsMenu: String { russian ? "Настройки…" : "Settings…" }
    static var language: String { russian ? "Язык" : "Language" }
    static var languageSystem: String { russian ? "Как в системе" : "Match System" }
    static var languageFootnote: String {
        russian
            ? "Выбор сохраняется на этом Mac."
            : "This choice is saved on this Mac."
    }
    static var helpMenu: String { russian ? "Справка по Grove" : "Grove Help" }
    static var aboutBody: String {
        russian
            ? "Grove показывает, чем занято место на диске. Карта строится на этом компьютере: имена файлов, пути и размеры никуда не отправляются."
            : "Grove shows what is using space on a disk. The map is built on this Mac: file names, paths, and sizes are not sent anywhere."
    }
    static var developer: String { russian ? "Разработчик" : "Developer" }
    static var aboutClose: String { russian ? "Закрыть" : "Close" }
}
