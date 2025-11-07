// The Swift Programming Language
// https://docs.swift.org/swift-book

import SwiftUI
import PhotosUI

// MARK: - High-level usage
// Put `EditorCanvasView()` anywhere (e.g. as your ContentView).
// Users can add text, add images from Photos, drag, pinch-to-zoom, and rotate.
// Supports drag & drop of images/text, simple z-order controls, and export.

struct EditorCanvasView: View {
    @StateObject private var model = EditorModel()
    @Environment(\.undoManager) private var undoManager

    @State private var showTextSheet = false
    @State private var selectedTextBinding: Binding<EditorLayer>? // used to edit text

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.secondarySystemBackground).ignoresSafeArea()
                GeometryReader { geo in
                    let size = geo.size
                    ZStack {
                        ForEach($model.layers) { $layer in
                            LayerView(layer: $layer)
                                .onTapGesture { model.select(layer.id) }
                                .simultaneousGesture(TapGesture(count: 2).onEnded {
                                    if case .text = layer.content {
                                        model.select(layer.id)
                                        selectedTextBinding = $layer
                                        showTextSheet = true
                                    }
                                })
                                .overlay(alignment: .center) {
                                    if model.selection == layer.id { SelectionBox() }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { model.selection = nil }
                    .onDrop(of: ["public.image", "public.text"], isTargeted: nil) { providers in
                        Task { @MainActor in
                            await model.handleDrop(providers, in: size)
                        }
                        return true
                    }
                }
            }
            .toolbar(content: {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { model.addText(); showTextSheet = true } label: {
                        Label("Text", systemImage: "textformat")
                    }
                    PhotosPicker(selection: $model.photoSelection, matching: .images, photoLibrary: .shared()) {
                        Label("Image", systemImage: "photo")
                    }
                    Spacer()
                    if let id = model.selection, let index = model.indexOfLayer(id) {
                        Menu {
                            Button("Bring Forward") { model.bringForward(index) }
                            Button("Send Backward") { model.sendBackward(index) }
                            Divider()
                            Button(role: .destructive) { model.deleteSelected() } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Label("Layer", systemImage: "square.3.layers.3d.top.filled")
                        }
                    }
                    Button { export() } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            })
            .sheet(isPresented: $showTextSheet) {
                if let $layer = selectedTextBinding { TextEditSheet(layer: $layer) }
            }
            .onChange(of: model.photoSelection) {
                Task { @MainActor in
                    await model.loadSelectedPhoto()
                }
            }
            .navigationTitle("Editor")
        }
    }

    private func export() {
        // Exports a 1080x1920 image of the canvas using the current layers.
        let exportSize = CGSize(width: 1080, height: 1920)
        let renderer = ImageRenderer(content:
            ZStack {
                Color.clear
                ForEach(model.layers) { layer in
                    LayerRenderView(layer: layer)
                }
            }
            .frame(width: exportSize.width, height: exportSize.height)
        )
        if let uiImage = renderer.uiImage {
            UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
        }
    }
}

// MARK: - Model

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

struct EditorLayer: Identifiable, Equatable {
    var id = UUID()
    var content: EditorContent
    var position: CGPoint = CGPoint(x: 150, y: 150)
    var scale: CGFloat = 1
    var rotation: Angle = .degrees(0)

    static func == (lhs: EditorLayer, rhs: EditorLayer) -> Bool { lhs.id == rhs.id }
}

enum EditorContent: Equatable { case text(TextModel), image(ImageModel) }

struct TextModel: Equatable {
    var text: String
    var fontSize: CGFloat = 28
    var color: Color = .primary
    var weight: Font.Weight = .bold

    init(text: String, fontSize: CGFloat = 28, color: Color = .primary, weight: Font.Weight = .bold) {
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.weight = weight
    }

    init(text: String) {
        self.text = text
        self.fontSize = 28
        self.color = .primary
        self.weight = .bold
    }
}

struct ImageModel: Equatable { var data: Data }

// MARK: - Layer rendering & interaction

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

struct SelectionBox: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
            .padding(-6)
    }
}

// MARK: - Text editing sheet

struct TextEditSheet: View {
    @Binding var layer: EditorLayer
    @State private var text: String = ""
    @State private var fontSize: Double = 28
    @State private var isBold = true
    @State private var color: Color = .primary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if case .text(let model) = layer.content {
                    Section("Text") {
                        TextField("Text", text: $text, axis: .vertical)
                            .onAppear {
                                text = model.text
                                fontSize = Double(model.fontSize)
                                isBold = model.weight == .bold
                                color = model.color
                            }
                    }
                    Section("Style") {
                        Stepper("Font size \(Int(fontSize))", value: $fontSize, in: 12...128)
                        Toggle("Bold", isOn: $isBold)
                        ColorPicker("Color", selection: $color)
                    }
                    Section("Preview") {
                        Text(text)
                            .font(.system(size: fontSize, weight: isBold ? .bold : .regular))
                            .foregroundStyle(color)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                }
            }
            .navigationTitle("Edit Text")
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        layer.content = .text(TextModel(text: text,
                                                      fontSize: CGFloat(fontSize),
                                                      color: color,
                                                      weight: isBold ? Font.Weight.bold : Font.Weight.regular))
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            })
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Preview

#Preview {
    EditorCanvasView()
}

