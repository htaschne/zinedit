//
//  LayerRenderView.swift
//  zinedit
//
//  Created by Agatha Schneider on 07/11/25.
//

import SwiftUI

struct LayerRenderView: View {
    let layer: EditorLayer
    var body: some View {
        Group {
            switch layer.content {
            case .text(let text):
                Text(text.text)
                    .font(.system(size: text.fontSize, weight: text.weight))
                    .foregroundStyle(text.color)
            case .image(let image):
                if let uiImage = UIImage(data: image.data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220)
                }
            }
        }
        .scaleEffect(layer.scale)
        .rotationEffect(layer.rotation)
        .offset(x: layer.position.x, y: layer.position.y)
    }
}
