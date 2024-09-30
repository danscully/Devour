//
//  DevourGuiApp.swift
//  DevourGui
//
//  Created by Dan Scully on 9/24/24.
//

import SwiftUI
import Foundation
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

class AppState: ObservableObject {
    @Published var importTrigger = false
}

@main
struct SwiftUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var importTrigger: Bool = false
    @StateObject var appState = AppState()

    var body: some Scene {
        Window ("Devour", id: "devour-id"){
            ContentView(appState: appState)
                .frame(minWidth: 800, minHeight: 600)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false
                }
            
        }.windowStyle(HiddenTitleBarWindowStyle())
            .windowResizability(.contentSize)
        
        .commands {
            CommandGroup(replacing: CommandGroupPlacement.textEditing) {
                EmptyView()
            }
            CommandGroup(replacing: CommandGroupPlacement.help) {
                EmptyView()
            }
            CommandGroup(replacing: CommandGroupPlacement.appVisibility) {
                EmptyView()
            }
            CommandGroup(replacing: CommandGroupPlacement.pasteboard) {
                EmptyView()
            }
            CommandGroup(replacing: CommandGroupPlacement.undoRedo) {
                EmptyView()
            }
            CommandGroup(replacing: CommandGroupPlacement.newItem) {
                Button("Open Video for Processing") {
                    appState.importTrigger = true
                    appState.importTrigger = false
                }.keyboardShortcut("o")
            }
        }
    }
}
