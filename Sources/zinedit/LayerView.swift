//
//  LayerView.swift
//  zinedit
//
//  Created by Agatha Schneider on 07/11/25.
//

import SwiftUI

struct LayerView: View {
    @Binding var layer: EditorLayer

    @State private var dragStart: CGPoint? = nil
    @State private var scaleStart: CGFloat? = nil
    @State private var rotationStart: Angle? = nil

    var body: some View {
        content
            .scaleEffect(layer.scale)
            .rotationEffect(layer.rotation)
            .offset(x: layer.position.x, y: layer.position.y)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStart == nil { dragStart = layer.position }
                        if let start = dragStart {
                            layer.position = CGPoint(x: start.x + value.translation.width,
                                                     y: start.y + value.translation.height)
                        }
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        if scaleStart == nil { scaleStart = layer.scale }
                        if let base = scaleStart { layer.scale = max(0.2, base * value) }
                    }
                    .onEnded { _ in scaleStart = nil }
            )
            .simultaneousGesture(
                RotationGesture()
                    .onChanged { value in
                        if rotationStart == nil { rotationStart = layer.rotation }
                        if let base = rotationStart { layer.rotation = base + value }
                    }
                    .onEnded { _ in rotationStart = nil }
            )
    }

    @ViewBuilder
    private var content: some View {
        switch layer.content {
        case .text(let text):
            Text(text.text)
                .font(.system(size: text.fontSize, weight: text.weight))
                .foregroundStyle(text.color)
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        case .image(let image):
            if let uiImage = UIImage(data: image.data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 2)
            } else {
                Color.gray.frame(width: 200, height: 200)
            }
        }
    }
}
