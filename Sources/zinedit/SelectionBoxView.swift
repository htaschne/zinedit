//
//  SelectionBox.swift
//  zinedit
//
//  Created by Agatha Schneider on 07/11/25.
//

import SwiftUI

struct SelectionBox: View {
    // TODO: this should be scaled, positioned and rotated along with it's content
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
            .padding(-6)
    }
}
