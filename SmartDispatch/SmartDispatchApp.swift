//
//  SmartDispatchApp.swift
//  SmartDispatch
//
//  Created by Julio Garcìa on 14/11/26.
//

import SwiftUI
import FirebaseAuth

@main
struct SmartDispatchApp: App {
    @StateObject private var store = AppStore()

    init() {
        if let firebaseAppClass = NSClassFromString("FIRApp") as? NSObject.Type {
            firebaseAppClass.perform(NSSelectorFromString("configure"))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

