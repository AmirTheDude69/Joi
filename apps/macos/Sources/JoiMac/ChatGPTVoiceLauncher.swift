import AppKit
import Foundation

enum ChatGPTVoiceLauncher {
    static let url = URL(string: "https://chatgpt.com/")!

    @MainActor
    static func open() -> Bool {
        NSWorkspace.shared.open(url)
    }
}
