// The Swift Programming Language
// https://docs.swift.org/swift-book

import SwiftUI
import PhotosUI

// MARK: - High-level usage
// Put `EditorCanvasView()` anywhere (e.g. as your ContentView).
// Users can add text, add images from Photos, drag, pinch-to-zoom, and rotate.
// Supports drag & drop of images/text, simple z-order controls, and export.

public struct EditorCanvasView: View {
    @Binding private var layers: [EditorLayer]
    private let config: EditorConfig
    private let onExport: ((UIImage) -> Void)?
    private let onChange: (([EditorLayer]) -> Void)?

    @StateObject private var model = EditorModel()
    @Environment(\.undoManager) private var undoManager

    @State private var showTextSheet = false
    @State private var selectedTextBinding: Binding<EditorLayer>? // used to edit text

    public init(layers: Binding<[EditorLayer]>,
                config: EditorConfig = .init(),
                onExport: ((UIImage) -> Void)? = nil,
                onChange: (([EditorLayer]) -> Void)? = nil) {
        self._layers = layers
        self.config = config
        self.onExport = onExport
        self.onChange = onChange
    }

    public var body: some View {
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
                    if config.showsPhotosPicker {
                        PhotosPicker(selection: $model.photoSelection, matching: .images, photoLibrary: .shared()) {
                            Label("Image", systemImage: "photo")
                        }
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
            // keep EditorModel and host binding in sync
            .onAppear {
                model.layers = layers
            }
            .onChange(of: model.layers) { _, newValue in
                self.layers = newValue
                self.onChange?(newValue)
            }
            .onChange(of: layers) { oldValue, newValue in
                if model.layers != newValue {
                    model.layers = newValue
                }
            }
            .navigationTitle("Editor")
        }
    }

    private func export() {
        let image = EditorRenderer.renderImage(layers: model.layers, size: config.exportSize)
        onExport?(image)
    }
}

// MARK: - Public API

public struct EditorConfig: Equatable {
    public var exportSize: CGSize
    public var showsPhotosPicker: Bool

    public init(exportSize: CGSize = CGSize(width: 1080, height: 1920),
                showsPhotosPicker: Bool = true) {
        self.exportSize = exportSize
        self.showsPhotosPicker = showsPhotosPicker
    }
}

public enum EditorRenderer {
    @MainActor public static func renderImage(layers: [EditorLayer], size: CGSize) -> UIImage {
        let renderer = ImageRenderer(content:
            ZStack {
                Color.clear
                ForEach(layers) { layer in
                    LayerRenderView(layer: layer)
                }
            }
            .frame(width: size.width, height: size.height)
        )
        return renderer.uiImage ?? UIImage()
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

public struct EditorLayer: Identifiable, Equatable {
    public var id: UUID
    public var content: EditorContent
    public var position: CGPoint
    public var scale: CGFloat
    public var rotation: Angle

    public init(id: UUID = UUID(),
                content: EditorContent,
                position: CGPoint = CGPoint(x: 150, y: 150),
                scale: CGFloat = 1,
                rotation: Angle = .degrees(0)) {
        self.id = id
        self.content = content
        self.position = position
        self.scale = scale
        self.rotation = rotation
    }

    public static func == (lhs: EditorLayer, rhs: EditorLayer) -> Bool { lhs.id == rhs.id }
}

public enum EditorContent: Equatable {
    case text(TextModel)
    case image(ImageModel)
}

public struct TextModel: Equatable {
    public var text: String
    public var fontSize: CGFloat
    public var color: Color
    public var weight: Font.Weight

    public init(text: String,
                fontSize: CGFloat = 28,
                color: Color = .primary,
                weight: Font.Weight = .bold) {
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.weight = weight
    }
}

public struct ImageModel: Equatable {
    public var data: Data
    public init(data: Data) { self.data = data }
}

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
    PreviewHost()
}

struct PreviewHost: View {
    @State var layers: [EditorLayer] = []
    var body: some View {
        EditorCanvasView(layers: $layers)
    }
}
