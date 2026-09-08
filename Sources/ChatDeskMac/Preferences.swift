import Foundation

final class Preferences {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var safeMode: Bool { get { defaults.bool(forKey: "safeMode") } set { defaults.set(newValue, forKey: "safeMode") } }
    var assistedPaste: Bool {
        get { defaults.object(forKey: "assistedPaste") == nil || defaults.bool(forKey: "assistedPaste") }
        set { defaults.set(newValue, forKey: "assistedPaste") }
    }
    var controlCV: Bool { get { defaults.bool(forKey: "controlCV") } set { defaults.set(newValue, forKey: "controlCV") } }
    var globalHotKey: Bool {
        get { defaults.object(forKey: "globalHotKey") == nil || defaults.bool(forKey: "globalHotKey") }
        set { defaults.set(newValue, forKey: "globalHotKey") }
    }
    var hotKeyUsesCommand: Bool {
        get { defaults.bool(forKey: "hotKeyUsesCommand") }
        set { defaults.set(newValue, forKey: "hotKeyUsesCommand") }
    }
    var zoom: Double {
        get { let value = defaults.double(forKey: "zoom"); return value >= 0.7 && value <= 2 ? value : 1 }
        set { defaults.set(min(2, max(0.7, newValue)), forKey: "zoom") }
    }
    var readingWidth: Int {
        get { defaults.integer(forKey: "readingWidth") }
        set { defaults.set(newValue, forKey: "readingWidth") }
    }
}
