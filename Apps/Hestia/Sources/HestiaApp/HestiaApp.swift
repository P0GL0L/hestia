import SwiftUI

@main
struct HestiaApp: App {
    @NSApplicationDelegateAdaptor(HestiaAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
