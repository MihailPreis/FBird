//
//  ContentView.swift
//  FBird
//
//  Created by Mike Price on 17.09.2024.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("🧸")
                .font(.largeTitle)
            
            Text("Привет!")
                .font(.title)
            
            Text("""
                 Тут ничего интересного нет. 
                 Как говорится: **cumming soon**!
                 
                 Просто ставь игрульку на свои часики и наслаждайся
                 """)
            .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
