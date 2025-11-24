//
//  LayerRenderView.swift
//  zinedit
//
//  Created by Agatha Schneider on 07/11/25.
//

import SwiftUI
#if canImport(PencilKit)
import PencilKit
#endif
#if canImport(UIKit)
import UIKit
#endif

struct LayerRenderView: View {
    let layer: EditorLayer
    var body: some View {
        Group {
            switch layer.content {
            case .text(let text):
                let italic = textIsItalic(text)
                if let name = text.fontName, !name.isEmpty {
                    if italic {
                        Text(text.text)
                            .font(.custom(name, size: text.fontSize))
                            .foregroundStyle(text.color)
                            .italic()
                    } else {
                        Text(text.text)
                            .font(.custom(name, size: text.fontSize))
                            .foregroundStyle(text.color)
                    }
                } else {
                    if italic {
                        Text(text.text)
                            .font(.system(size: text.fontSize, weight: text.weight))
                            .foregroundStyle(text.color)
                            .italic()
                    } else {
                        Text(text.text)
                            .font(.system(size: text.fontSize, weight: text.weight))
                            .foregroundStyle(text.color)
                    }
                }
            case .image(let image):
                if let uiImage = UIImage(data: image.data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220)
                }
            #if canImport(PencilKit)
            case .drawing(let drawing):
                if let pkDrawing = try? PKDrawing(data: drawing.data) {
                    let rect = CGRect(origin: .zero, size: drawing.size)
                    #if canImport(UIKit)
                    let scale = UIScreen.main.scale
                    #else
                    let scale: CGFloat = 2.0
                    #endif
                    let uiImage = pkDrawing.image(from: rect, scale: scale)
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220)
                }
            #else
            case .drawing(_):
                Text("Drawing not supported on this platform")
                    .font(.footnote)
            #endif
            }
        }
        .scaleEffect(layer.scale)
        .rotationEffect(layer.rotation)
        .offset(x: layer.position.x, y: layer.position.y)
    }
}

// Helper: checks for a Bool `isItalic` on TextModel without requiring the property to exist at compile-time.
private func textIsItalic(_ t: TextModel) -> Bool {
    let mirror = Mirror(reflecting: t)
    for child in mirror.children {
        if child.label == "isItalic", let b = child.value as? Bool {
            return b
        }
    }
    return false
}
