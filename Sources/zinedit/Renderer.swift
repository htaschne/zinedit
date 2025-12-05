//
//  Renderer.swift
//  zine
//
//  Created by Endrew Soares on 03/12/25.
//

import SwiftUI
import UIKit

struct Renderer {
    
    @MainActor
    static func renderMyViewAsUIImage<V: View>(swiftUIView: V) -> UIImage? {
        let renderer = ImageRenderer(content: swiftUIView)
        renderer.scale = UIScreen.main.scale   // optional, for retina
        //swiftUIView.window?.windowScene?.screen.scale
        return renderer.uiImage
    }
}
