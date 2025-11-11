//
//  EditorModel.swift
//  zinedit
//
//  Created by Agatha Schneider on 07/11/25.
//


import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(PencilKit)
import PencilKit
#endif

@MainActor
final class EditorModel: ObservableObject {
    @Published var layers: [EditorLayer] = []
    @Published var selection: UUID?
    @Published var photoSelection: PhotosPickerItem?

    func select(_ id: UUID) {
        selection = id
    }

    func indexOfLayer(_ id: UUID) -> Int? {
        layers.firstIndex(where: { $0.id == id })
    }

    func bringForward(_ index: Int) {
        guard index < layers.count - 1 else { return }
        layers.swapAt(index, index + 1)
    }

    func sendBackward(_ index: Int) {
        guard index > 0 else { return }
        layers.swapAt(index, index - 1)
    }

    func deleteSelected() {
        if let id = selection, let index = indexOfLayer(id) {
            layers.remove(at: index)
            selection = nil
        }
    }

    func addText() {
        let layer = EditorLayer(content: .text(TextModel(text: "New Text")))
        layers.append(layer)
        selection = layer.id
    }

    func addImage(_ data: Data, at point: CGPoint? = nil) {
        var layer = EditorLayer(content: .image(ImageModel(data: data)))
        if let p = point { layer.position = p }
        layers.append(layer)
        selection = layer.id
    }

    #if canImport(PencilKit)
    func addDrawing(baseSize: CGSize) {
        let empty = PKDrawing().dataRepresentation()
        var layer = EditorLayer(content: .drawing(DrawingModel(data: empty, size: baseSize)))
        layer.position = CGPoint(x: 160, y: 160)
        layers.append(layer)
        selection = layer.id
    }
    #endif

    func handleDrop(_ providers: [NSItemProvider], in size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        for p in providers {
            if p.canLoadObject(ofClass: UIImage.self) {
                p.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage, let data = image.pngData() {
                        Task { @MainActor in
                            self.addImage(data, at: center)
                        }
                    }
                }
                return
            } else if p.canLoadObject(ofClass: NSString.self) {
                p.loadObject(ofClass: NSString.self) { object, _ in
                    if let string = object as? String {
                        Task { @MainActor in
                            var layer = EditorLayer(content: .text(TextModel(text: String(string))))
                            layer.position = center
                            self.layers.append(layer)
                            self.selection = layer.id
                        }
                    }
                }
                return
            }
        }
    }

    func loadSelectedPhoto() async {
        guard let item = photoSelection else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            addImage(data)
        }
        photoSelection = nil
    }
}

