//
//  View.swift
//  TimeMachinePlusPlus
//
//  Created by Artem Bagin on 08.06.2026.
//

import SwiftUI

extension View {
    func previewModifiers(setSize: Bool = true) -> some View {
        frame(width: setSize ? 600 : nil, height: setSize ? 600 : nil)
            .scenePadding()
            .environment(AppStateStore())
    }
}
