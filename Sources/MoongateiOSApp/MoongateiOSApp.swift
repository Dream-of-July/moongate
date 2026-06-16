import SwiftUI
import MoongateiOS

@main
struct MoongateiOSApp: App {
    @StateObject private var model = IOSMobileAppModel.live()

    var body: some Scene {
        WindowGroup {
            MoongateIOSRootView(model: model)
                .task {
                    await model.restoreQueueFromRepository()
                }
        }
    }
}
