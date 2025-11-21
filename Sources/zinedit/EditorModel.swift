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

    // MARK: - Undo/Redo (last 5 snapshots)
    private var history: [[EditorLayer]] = []
    private var future: [[EditorLayer]] = []
    private let historyLimit: Int = 5

    var canUndo: Bool { !history.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    func select(_ id: UUID) {
        selection = id
    }

    func indexOfLayer(_ id: UUID) -> Int? {
        layers.firstIndex(where: { $0.id == id })
    }

    func bringForward(_ index: Int) {
        guard index < layers.count - 1 else { return }
        registerUndoPoint()
        layers.swapAt(index, index + 1)
    }

    func sendBackward(_ index: Int) {
        guard index > 0 else { return }
        registerUndoPoint()
        layers.swapAt(index, index - 1)
    }

    func deleteSelected() {
        registerUndoPoint()
        if let id = selection, let index = indexOfLayer(id) {
            layers.remove(at: index)
            selection = nil
        }
    }

    func addText() {
        registerUndoPoint()
        let layer = EditorLayer(content: .text(TextModel(text: "New Text")))
        layers.append(layer)
        selection = layer.id
    }

    func addImage(_ data: Data, at point: CGPoint? = nil) {
        registerUndoPoint()
        var layer = EditorLayer(content: .image(ImageModel(data: data)))
        if let p = point { layer.position = p }
        layers.append(layer)
        selection = layer.id
    }

    #if canImport(PencilKit)
    func addDrawing(baseSize: CGSize) {
        registerUndoPoint()
        let empty = PKDrawing().dataRepresentation()
        var layer = EditorLayer(content: .drawing(DrawingModel(data: empty, size: baseSize)))
        layer.position = CGPoint(x: 160, y: 160)
        layers.append(layer)
        selection = layer.id
    }
    #endif

    // Capture the current state BEFORE a mutation
    func registerUndoPoint() {
        history.append(layers)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
        future.removeAll()
    }

    func undo() {
        guard let previous = history.popLast() else { return }
        future.append(layers)
        layers = previous
        selection = nil
    }

    func redo() {
        guard let next = future.popLast() else { return }
        history.append(layers)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
        layers = next
        selection = nil
    }

    func handleDrop(_ providers: [NSItemProvider], in size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        for p in providers {
            if p.canLoadObject(ofClass: UIImage.self) {
                p.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage, let data = image.pngData() {
                        Task { @MainActor in
                            self.registerUndoPoint()
                            self.addImage(data, at: center)
                        }
                    }
                }
                return
            } else if p.canLoadObject(ofClass: NSString.self) {
                p.loadObject(ofClass: NSString.self) { object, _ in
                    if let string = object as? String {
                        Task { @MainActor in
                            self.registerUndoPoint()
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
