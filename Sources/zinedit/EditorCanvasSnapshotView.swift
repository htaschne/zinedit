//
//  EditorCanvasSnapshotView.swift
//  zinedit
//
//  Created by Endrew Soares on 09/12/25.
//

import SwiftUI
import Foundation

struct EditorCanvasSnapshotView: View {
    let layers: [EditorLayer]
    let canvasSize: CGSize
    let selection: UUID?

    var body: some View {
        ZStack {
            Color("SystemLightDarkSystemBackground")

            ForEach(layers) { layer in
                if !layer.isHidden {
                    LayerRenderView(layer: layer)
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
