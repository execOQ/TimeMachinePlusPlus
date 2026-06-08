//
//  View.swift
//  TimeMachinePlusPlus
//
//  Created by Artem Bagin on 08.06.2026.
//

import SwiftUI

extension View {
    func previewModifiers() -> some View {
        frame(width: 600, height: 600)
            .scenePadding()
            .environment(AppStateStore())
    }
}
