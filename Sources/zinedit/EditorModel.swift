//
//  EditorModel.swift
//  zinedit
//
//  Created by Agatha Schneider on 07/11/25.
//

import SwiftUI
import PhotosUI

@MainActor
final class EditorModel: ObservableObject {
    @Published var layers: [EditorLayer] = []
    @Published var selection: UUID?
    @Published var photoSelection: PhotosPickerItem?

    func addText() {
        var layer = EditorLayer(content: .text(.init(text: "Double‑tap to edit")))
        layer.position = CGPoint(x: 160, y: 160)
        layers.append(layer)
        selection = layer.id
    }

    func addImage(_ data: Data, at point: CGPoint? = nil) {
        var layer = EditorLayer(content: .image(.init(data: data)))
        if let p = point { layer.position = p }
        layers.append(layer)
        selection = layer.id
    }

    func deleteSelected() {
        guard let id = selection, let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        layers.remove(at: idx)
        selection = nil
    }

    func select(_ id: UUID) { selection = id }

    func indexOfLayer(_ id: UUID) -> Int? { layers.firstIndex { $0.id == id } }

    func bringForward(_ index: Int) {
        guard index < layers.count - 1 else { return }
        layers.swapAt(index, index + 1)
    }

    func sendBackward(_ index: Int) {
        guard index > 0 else { return }
        layers.swapAt(index, index - 1)
    }

    // Drag & Drop support for iPadOS/macOS (works on iPhone in split view too)
    @MainActor
    func handleDrop(_ providers: [NSItemProvider], in canvasSize: CGSize) async {
        let model = self
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        for p in providers {
            if p.canLoadObject(ofClass: UIImage.self) {
                p.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage, let data = image.pngData() {
                        Task { @MainActor in
                            model.addImage(data, at: center)
                        }
                    }
                }
                return
            } else if p.canLoadObject(ofClass: NSString.self) {
                p.loadObject(ofClass: NSString.self) { object, _ in
                    if let string = object as? String {
                        Task { @MainActor in
                            var layer = EditorLayer(content: .text(.init(text: string)))
                            layer.position = center
                            model.layers.append(layer)
                            model.selection = layer.id
                        }
                    }
                }
                return
            }
        }
    }

    @MainActor
    func loadSelectedPhoto() async {
        guard let item = photoSelection else { return }
        if let data = try? await item.loadTransferable(type: Data.self) { addImage(data) }
        photoSelection = nil
    }
}
