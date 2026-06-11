//
//  InfoPopView.swift
//  FollowPhoto
//
//  Created by Artem Bagin on 17.02.2026.
//

#if os(macOS)

import SwiftUI

struct InfoPopView: View {
    let color: Color
    let description: LocalizedStringKey
    @State var isShowingDescription: Bool = false
    @State var isHovering: Bool = false

    @State var hoverTimer: Timer?

    init(_ description: LocalizedStringKey, _ color: Color = .accentColor) {
        self.color = color
        self.description = description
    }

    var body: some View {
        Group {
            Circle()
                .frame(width: 5, height: 5)
                .contentShape(.circle)
                .foregroundStyle(color)
                .onHover { hovering in
                    isHovering = hovering

                    if isHovering {
                        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { _ in
                            isShowingDescription = true
                        }
                    } else {
                        hoverTimer?.invalidate()
                        isShowingDescription = false
                    }
                }
                .popover(isPresented: $isShowingDescription, arrowEdge: .bottom) {
                    Text(description)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 350, alignment: .center)
                        .padding(6)
                }
        }
        .offset(x: 6)
    }
}
#endif
