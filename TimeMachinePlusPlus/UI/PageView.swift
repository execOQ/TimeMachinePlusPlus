//
//  PageView.swift
//  TimeMachinePlusPlus
//
//  Created by Artem Bagin on 19.05.2026.
//

import SwiftUI

struct PageView<Content: View>: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey = ""
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
    }
}
