import SwiftUI

@main
struct SmartPrompterApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            PrompterView(model: model)
                .frame(minWidth: 340, minHeight: 420)
        }
        .defaultSize(width: 390, height: 640)
        .windowResizability(.contentMinSize)
        .windowBackgroundDragBehavior(.enabled)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Call") {
                Button("Show Cue Panel") {
                    model.showCuePanel()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!model.isListening)

                Divider()

                Button(model.isListening ? "Stop Listening" : "Start Listening") {
                    Task {
                        if model.isListening {
                            await model.stop()
                        } else {
                            await model.start()
                        }
                    }
                }
                .keyboardShortcut(.space, modifiers: [.command, .shift])
            }
        }
    }
}
