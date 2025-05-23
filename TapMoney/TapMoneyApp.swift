//
//  TapMoneyApp.swift
//  TapMoney
//
//  Created by HONGYINULL on 2025/5/23.
//

import SwiftUI

@main
struct TapMoneyApp: App {
    
    init() {
            let accentColor = UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                ? UIColor(.yellow)  // 暗色模式
                : UIColor(.orange)    // 亮色模式
//                ? UIColor(red: 153/255, green: 31/255, blue: 34/255, alpha: 1)  // 暗色模式
//                : UIColor(red: 107/255, green: 0/255, blue: 6/255, alpha: 1)    // 亮色模式
            }
            UIView.appearance().tintColor = accentColor
        }
    
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: ExpenseEntry.self)
    }
}
