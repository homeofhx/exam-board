import AppKit
import SwiftUI

@main
struct ExamBoardMain {
    public static func main() {
        let app = NSApplication.shared
        let delegate = ExamBoardAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class ExamBoardAppDelegate: NSObject, NSApplicationDelegate {
    
    private var windowController: MainWindowController?
    
    private let viewModel = ExamBoardViewModel()
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = ContentView(viewModel: viewModel)
        let controller = MainWindowController(rootView: contentView)
        windowController = controller
        controller.showWindow(nil)
        bringAppToFront()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.bringAppToFront()
            self?.windowController?.showWindow(nil)
            self?.windowController?.window?.makeKeyAndOrderFront(nil)
            self?.windowController?.window?.orderFrontRegardless()
        }
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        bringAppToFront()
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
        windowController?.window?.orderFrontRegardless()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
    
    @objc private func openLatestRelease() {
        if let url = URL(string: "https://github.com/homeofhx/exam-board/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func bringAppToFront() {
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    }
    
    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        
        let releaseItem = NSMenuItem(title: "Get Latest Release", action: #selector(openLatestRelease), keyEquivalent: "")
        releaseItem.target = self
        appMenu.addItem(releaseItem)
        
        appMenu.addItem(withTitle: "Quit!", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        return mainMenu
    }
    
}

@MainActor
final class MainWindowController: NSWindowController {
    
    init(rootView: some View) {
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Exam Board"
        window.contentView = hostingView
        window.center()
        super.init(window: window)
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
