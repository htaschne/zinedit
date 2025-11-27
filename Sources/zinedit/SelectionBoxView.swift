//
//  SelectionBox.swift
//  zinedit
//
//  Created by Agatha Schneider on 07/11/25.
//

import SwiftUI

struct SelectionBox: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
            .foregroundStyle(Color("BrandZinerPrimary100"))
            .padding(-6)
    }
}
