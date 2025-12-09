//
//  Untitled.swift
//  zinedit
//
//  Created by Endrew Soares on 09/12/25.
//

import SwiftUI

@MainActor
enum HighResSnapshotRenderer {
    static func render<V: View>(
        _ view: V,
        size: CGSize,
        scale: CGFloat = 3.0
    ) -> UIImage {

        let controller = UIHostingController(rootView:
            view
                .frame(width: size.width, height: size.height)
        )

        controller.view.bounds = CGRect(origin: .zero, size: size)
        controller.view.backgroundColor = .clear
        controller.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            controller.view.drawHierarchy(
                in: controller.view.bounds,
                afterScreenUpdates: true
            )
        }
    }
}
