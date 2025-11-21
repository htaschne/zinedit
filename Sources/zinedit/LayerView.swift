//
//  LayerView.swift
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

struct LayerView: View {
    @Binding var layer: EditorLayer
    var onBeginInteraction: (() -> Void)? = nil

    @State private var dragStart: CGPoint? = nil
    @State private var scaleStart: CGFloat? = nil
    @State private var rotationStart: Angle? = nil
    @State private var beganDrag = false
    @State private var beganScale = false
    @State private var beganRotate = false

    var body: some View {
        content
            .scaleEffect(layer.scale)
            .rotationEffect(layer.rotation)
            .offset(x: layer.position.x, y: layer.position.y)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !beganDrag { beganDrag = true; onBeginInteraction?() }
                        if dragStart == nil { dragStart = layer.position }
                        if let start = dragStart {
                            layer.position = CGPoint(
                                x: start.x + value.translation.width,
                                y: start.y + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in beganDrag = false; dragStart = nil }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        if !beganScale { beganScale = true; onBeginInteraction?() }
                        if scaleStart == nil { scaleStart = layer.scale }
                        if let base = scaleStart {
                            layer.scale = max(0.2, base * value)
                        }
                    }
                    .onEnded { _ in beganScale = false; scaleStart = nil }
            )
            .simultaneousGesture(
                RotationGesture()
                    .onChanged { value in
                        if !beganRotate { beganRotate = true; onBeginInteraction?() }
                        if rotationStart == nil {
                            rotationStart = layer.rotation
                        }
                        if let base = rotationStart {
                            layer.rotation = base + value
                        }
                    }
                    .onEnded { _ in beganRotate = false; rotationStart = nil }
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
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(cornerRadius: 8)
                )
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
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 2)
                } else {
                    Color.gray.frame(width: 200, height: 200)
                }
        #else
            case .drawing(_):
                Text("Drawing not supported on this platform")
                    .font(.footnote)
                    .padding(8)
                    .background(
                        .thinMaterial,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
        #endif
        }
    }
}
