import CoreImage
import CoreImage.CIFilterBuiltins
import PhotosUI
import SwiftUI

// Paint support
#if canImport(PencilKit)
    import PencilKit
#endif
#if canImport(UIKit)
    import UIKit
#endif

// MARK: - Public API
public struct EditorCanvasView: View {
    @Binding private var layers: [EditorLayer]
    private let config: EditorConfig
    private let onExport: ((UIImage) -> Void)?
    private let onChange: (([EditorLayer]) -> Void)?

    @StateObject private var model = EditorModel()
    @Environment(\.undoManager) private var undoManager

    @State private var showTextSheet = false
    #if canImport(PencilKit)
        @State private var showDrawingSheet = false
        @State private var selectedDrawingBinding: Binding<EditorLayer>?
    #endif
    @State private var showLayersSheet = false
    @State private var canvasSize: CGSize = .zero
    @State private var selectedTextBinding: Binding<EditorLayer>?  // used to edit text
    @State private var showNoiseSheet = false
    @State private var selectedImageBinding: Binding<EditorLayer>?

    public init(
        layers: Binding<[EditorLayer]>,
        config: EditorConfig = .init(),
        onExport: ((UIImage) -> Void)? = nil,
        onChange: (([EditorLayer]) -> Void)? = nil
    ) {
        self._layers = layers
        self.config = config
        self.onExport = onExport
        self.onChange = onChange
    }

    public init(
        restoredLayers: [EditorLayer],
        config: EditorConfig = .init(),
        onExport: ((UIImage) -> Void)? = nil,
        onChange: (([EditorLayer]) -> Void)? = nil
    ) {
        self._layers = .constant(restoredLayers) // one-way binding; use onChange to persist changes
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
                            if !layer.isHidden {
                                LayerView(layer: $layer)
                                    .onTapGesture { model.select(layer.id) }
                                    .simultaneousGesture(
                                        TapGesture(count: 2).onEnded {
                                            switch layer.content {
                                            case .text:
                                                model.select(layer.id)
                                                selectedTextBinding = $layer
                                                showTextSheet = true
                                            case .drawing:
                                                #if canImport(PencilKit)
                                                    model.select(layer.id)
                                                    selectedDrawingBinding = $layer
                                                    showDrawingSheet = true
                                                #endif
                                            default:
                                                break
                                            }
                                        }
                                    )
                                    .overlay {
                                        if model.selection == layer.id && !layer.isHidden {
                                            SelectionBox()
                                                .allowsHitTesting(false)
                                                .scaleEffect(layer.scale)
                                                .rotationEffect(layer.rotation)
                                                .offset(x: layer.position.x, y: layer.position.y)
                                        }
                                    }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { model.selection = nil }
                    .onDrop(
                        of: ["public.image", "public.text"],
                        isTargeted: nil
                    ) { providers in
                        model.handleDrop(providers, in: size)
                        return true
                    }
                    .onAppear { canvasSize = size }
                    .onChange(of: size) { _, newSize in canvasSize = newSize }
                }
            }
            .toolbar(content: {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        model.addText()
                        if let id = model.selection, let binding = bindingForLayer(id) {
                            selectedTextBinding = binding
                            showTextSheet = true
                        }
                    } label: {
                        Label("Text", systemImage: "textformat")
                    }
                    if config.showsPhotosPicker {
                        PhotosPicker(
                            selection: $model.photoSelection,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label("Image", systemImage: "photo")
                        }
                    }
                    #if canImport(PencilKit)
                        if config.paint != nil {
                            Button {
                                model.addDrawing(baseSize: canvasSize)
                                if let id = model.selection,
                                    let binding = bindingForLayer(id)
                                {
                                    selectedDrawingBinding = binding
                                    showDrawingSheet = true
                                }
                            } label: {
                                Label("Paint", systemImage: "pencil.tip")
                            }
                        }
                    #endif
                    // Noise button for image layers
                    if let id = model.selection,
                        let index = model.indexOfLayer(id)
                    {
                        if case .image = model.layers[index].content {
                            Button {
                                if let binding = bindingForLayer(id) {
                                    selectedImageBinding = binding
                                    showNoiseSheet = true
                                }
                            } label: {
                                Label("Noise", systemImage: "pencil.tip")
                            }
                        }
                    }
                    Spacer()
                    Button {
                        showLayersSheet = true
                    } label: {
                        Label("Layers", systemImage: "square.3.layers.3d.top.filled")
                    }
                    Button {
                        export()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            })
            .sheet(isPresented: $showTextSheet) {
                if let $layer = selectedTextBinding {
                    TextEditSheet(layer: $layer)
                }
            }
            #if canImport(PencilKit)
                .sheet(isPresented: $showDrawingSheet) {
                    if let $layer = selectedDrawingBinding,
                        let paint = config.paint
                    {
                        DrawingEditSheet(layer: $layer, config: paint)
                    }
                }
            #endif
            .sheet(isPresented: $showNoiseSheet) {
                if let $layer = selectedImageBinding {
                    NoiseEditSheet(layer: $layer)
                }
            }
            .sheet(isPresented: $showLayersSheet) {
                LayersSheet(layers: $model.layers, selection: $model.selection)
            }
            .onChange(of: model.photoSelection) { _, _ in
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

    private func bindingForLayer(_ id: UUID) -> Binding<EditorLayer>? {
        guard let index = model.indexOfLayer(id) else { return nil }
        return $model.layers[index]
    }

    private func export() {
        let image = EditorRenderer.renderImage(
            layers: model.layers,
            size: config.exportSize
        )
        onExport?(image)
    }
}

public struct EditorConfig: Equatable {
    public var exportSize: CGSize
    public var showsPhotosPicker: Bool
    public var paint: PaintConfig?  // nil disables paint features

    public init(
        exportSize: CGSize = CGSize(width: 1080, height: 1920),
        showsPhotosPicker: Bool = true,
        paint: PaintConfig? = nil
    ) {
        self.exportSize = exportSize
        self.showsPhotosPicker = showsPhotosPicker
        self.paint = paint
    }
}

// MARK: - Paint / Drawing public types

public struct EditorBrush: Equatable {
    public enum Kind: Equatable { case pen, marker, pencil }
    public var kind: Kind
    public var name: String
    public var color: Color
    public var width: CGFloat

    public init(kind: Kind, name: String, color: Color, width: CGFloat) {
        self.kind = kind
        self.name = name
        self.color = color
        self.width = width
    }
}

public enum EraserMode: Equatable { case vector, bitmap }

public struct PaintConfig: Equatable {
    public var brushes: [EditorBrush]  // recommend exactly 3
    public var eraser: EraserMode
    public var allowsFingerDrawing: Bool
    public var showsAppleToolPicker: Bool

    public init(
        brushes: [EditorBrush],
        eraser: EraserMode = .vector,
        allowsFingerDrawing: Bool = true,
        showsAppleToolPicker: Bool = false
    ) {
        self.brushes = brushes
        self.eraser = eraser
        self.allowsFingerDrawing = allowsFingerDrawing
        self.showsAppleToolPicker = showsAppleToolPicker
    }
}

/// Vector drawing payload compatible with PencilKit's PKDrawing via `dataRepresentation()`.
/// Store `size` as the base canvas size for accurate scaling during export.
public struct DrawingModel: Equatable, Codable {
    public var data: Data
    public var size: CGSize

    public init(data: Data, size: CGSize) {
        self.data = data
        self.size = size
    }
}

public enum EditorRenderer {
    @MainActor public static func renderImage(
        layers: [EditorLayer],
        size: CGSize
    ) -> UIImage {
        let renderer = ImageRenderer(
            content:
                ZStack {
                    Color.clear
                    ForEach(layers.filter { !$0.isHidden }) { layer in
                        LayerRenderView(layer: layer)
                    }
                }
                .frame(width: size.width, height: size.height)
        )
        return renderer.uiImage ?? UIImage()
    }
}

public struct EditorLayer: Identifiable, Equatable, Codable {

    public var id: UUID
    public var content: EditorContent
    public var position: CGPoint
    public var scale: CGFloat
    public var rotation: Angle
    public var isHidden: Bool
    
    public init(
        id: UUID = UUID(),
        content: EditorContent,
        position: CGPoint = CGPoint(x: 150, y: 150),
        scale: CGFloat = 1,
        rotation: Angle = .degrees(0),
        isHidden: Bool = false
    ) {
        self.id = id
        self.content = content
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.isHidden = isHidden
    }

    public static func == (lhs: EditorLayer, rhs: EditorLayer) -> Bool {
        lhs.id == rhs.id
    }
}

extension EditorLayer {
    private enum CodingKeys: String, CodingKey { case id, content, position, scale, rotationDegrees, isHidden }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.content = try c.decode(EditorContent.self, forKey: .content)
        self.position = try c.decode(CGPoint.self, forKey: .position)
        self.scale = try c.decode(CGFloat.self, forKey: .scale)
        let deg = try c.decode(Double.self, forKey: .rotationDegrees)
        self.rotation = .degrees(deg)
        self.isHidden = try c.decode(Bool.self, forKey: .isHidden)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(content, forKey: .content)
        try c.encode(position, forKey: .position)
        try c.encode(scale, forKey: .scale)
        try c.encode(rotation.degrees, forKey: .rotationDegrees)
        try c.encode(isHidden, forKey: .isHidden)
    }
}

public enum EditorContent: Equatable, Codable {
    case text(TextModel)
    case image(ImageModel)
    case drawing(DrawingModel)
}

extension EditorContent {
    private enum CodingKeys: String, CodingKey { case type, text, image, drawing }
    private enum Kind: String, Codable { case text, image, drawing }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .text:
            let value = try container.decode(TextModel.self, forKey: .text)
            self = .text(value)
        case .image:
            let value = try container.decode(ImageModel.self, forKey: .image)
            self = .image(value)
        case .drawing:
            let value = try container.decode(DrawingModel.self, forKey: .drawing)
            self = .drawing(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode(Kind.text, forKey: .type)
            try container.encode(value, forKey: .text)
        case .image(let value):
            try container.encode(Kind.image, forKey: .type)
            try container.encode(value, forKey: .image)
        case .drawing(let value):
            try container.encode(Kind.drawing, forKey: .type)
            try container.encode(value, forKey: .drawing)
        }
    }
}

public struct TextModel: Equatable, Codable {

    public var text: String
    public var fontSize: CGFloat
    public var color: Color
    public var weight: Font.Weight

    public init(
        text: String,
        fontSize: CGFloat = 28,
        color: Color = .primary,
        weight: Font.Weight = .bold
    ) {
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.weight = weight
    }
}

extension TextModel {
    private enum CodingKeys: String, CodingKey { case text, fontSize, color, weight }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try c.decode(String.self, forKey: .text)
        self.fontSize = try c.decode(CGFloat.self, forKey: .fontSize)
        let rgba = try c.decode(RGBA.self, forKey: .color)
        self.color = rgba.makeColor()
        let w = try c.decode(String.self, forKey: .weight)
        self.weight = Font.Weight.fromName(w)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encode(fontSize, forKey: .fontSize)
        try c.encode(color.rgba(), forKey: .color)
        try c.encode(weight.name, forKey: .weight)
    }
}

public struct ImageModel: Equatable, Codable {
    public var data: Data
    public init(data: Data) { self.data = data }
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

struct LayersSheet: View {
    @Binding var layers: [EditorLayer]
    @Binding var selection: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(layers.indices, id: \.self) { idx in
                    let layer = layers[idx]
                    HStack(spacing: 12) {
                        LayerRowThumb(layer: layer)
                            .frame(width: 44, height: 44)
                        Text(title(for: layer))
                            .lineLimit(1)
                            .foregroundStyle(selection == layer.id ? .primary : .secondary)
                        Spacer()
                        Button {
                            layers[idx].isHidden.toggle()
                            if layers[idx].isHidden, selection == layer.id {
                                selection = nil
                            }
                        } label: {
                            Image(systemName: layers[idx].isHidden ? "eye" : "eye.slash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(layers[idx].isHidden ? "Show layer" : "Hide layer")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = layer.id }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            layers[idx].isHidden.toggle()
                            if layers[idx].isHidden, selection == layer.id {
                                selection = nil
                            }
                        } label: {
                            if layers[idx].isHidden {
                                Label("Show", systemImage: "eye")
                            } else {
                                Label("Hide", systemImage: "eye.slash")
                            }
                        }
                    }
                }
                .onMove(perform: move)
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Layers")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        layers.move(fromOffsets: source, toOffset: destination)
    }

    private func title(for layer: EditorLayer) -> String {
        switch layer.content {
        case .text(let t):
            let s = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? "Text" : s
        case .image:
            return "Image"
        case .drawing:
            return "Drawing"
        }
    }
}

struct LayerRowThumb: View {
    let layer: EditorLayer
    var body: some View {
        ZStack {
            switch layer.content {
            case .image(let imageModel):
                if let ui = UIImage(data: imageModel.data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary
                }
            case .drawing(let drawingModel):
                #if canImport(PencilKit)
                if let pk = try? PKDrawing(data: drawingModel.data) {
                    let rect = CGRect(origin: .zero, size: drawingModel.size)
                    #if canImport(UIKit)
                    let scale = UIScreen.main.scale
                    #else
                    let scale: CGFloat = 2.0
                    #endif
                    let ui = pk.image(from: rect, scale: scale)
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary
                }
                #else
                Color.secondary
                #endif
            case .text(let t):
                Text(t.text)
                    .font(.system(size: 12, weight: t.weight))
                    .foregroundStyle(t.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(.thinMaterial)
            }
        }
        .frame(width: 44, height: 44)
        .clipped()
        .opacity(layer.isHidden ? 0.35 : 1)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.separator), lineWidth: 1))
    }
}

#if canImport(PencilKit)
    struct DrawingEditSheet: View {
        @Binding var layer: EditorLayer
        let config: PaintConfig
        @Environment(\.dismiss) private var dismiss
        @State private var data: Data = Data()
        @State private var selectedBrushIndex: Int = 0
        @State private var erasing: Bool = false

        private var baseSize: CGSize {
            if case .drawing(let m) = layer.content { return m.size }
            return CGSize(width: 1080, height: 1920)
        }

        var body: some View {
            NavigationStack {
                VStack(spacing: 12) {
                    // Brush/Eraser controls
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(
                                Array(config.brushes.enumerated()),
                                id: \.offset
                            ) { idx, brush in
                                Button {
                                    selectedBrushIndex = idx
                                    erasing = false
                                } label: {
                                    Text(brush.name)
                                        .padding(.horizontal, 10)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(
                                    (selectedBrushIndex == idx && !erasing)
                                        ? .accentColor : .secondary
                                )
                            }
                            Button {
                                erasing.toggle()
                            } label: {
                                Image(systemName: "eraser")
                                    .padding(.horizontal, 10)
                            }
                            .buttonStyle(.bordered)
                            .tint(erasing ? .accentColor : .secondary)
                        }
                        .padding(.horizontal, 12)
                    }

                    // Canvas
                    PencilCanvasView(
                        data: $data,
                        baseSize: baseSize,
                        config: config,
                        selectedBrush: safeSelectedBrush,
                        erasing: erasing
                    )
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 12)
                }
                .navigationTitle("Edit Drawing")
                .toolbar(content: {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Apply") {
                            layer.content = .drawing(
                                DrawingModel(data: data, size: baseSize)
                            )
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                })
                .onAppear {
                    if case .drawing(let m) = layer.content {
                        self.data = m.data
                    }
                }
            }
        }

        private var safeSelectedBrush: EditorBrush {
            if config.brushes.indices.contains(selectedBrushIndex) {
                return config.brushes[selectedBrushIndex]
            }
            return config.brushes.first
                ?? EditorBrush(kind: .pen, name: "Pen", color: .black, width: 3)
        }
    }

    struct PencilCanvasView: UIViewRepresentable {
        @Binding var data: Data
        var baseSize: CGSize
        var config: PaintConfig
        var selectedBrush: EditorBrush
        var erasing: Bool

        func makeUIView(context: Context) -> PKCanvasView {
            let canvas = PKCanvasView(
                frame: CGRect(origin: .zero, size: baseSize)
            )
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.drawingPolicy =
                config.allowsFingerDrawing ? .anyInput : .pencilOnly
            if let drawing = try? PKDrawing(data: data) {
                canvas.drawing = drawing
            }
            canvas.delegate = context.coordinator
            applyTool(to: canvas)
            return canvas
        }

        func updateUIView(_ canvas: PKCanvasView, context: Context) {
            if let drawing = try? PKDrawing(data: data) {
                if canvas.drawing != drawing { canvas.drawing = drawing }
            }
            applyTool(to: canvas)
        }

        func makeCoordinator() -> Coordinator { Coordinator(self) }

        private func applyTool(to canvas: PKCanvasView) {
            if erasing {
                let mode: PKEraserTool.EraserType =
                    (config.eraser == .bitmap) ? .bitmap : .vector
                canvas.tool = PKEraserTool(mode)
            } else {
                let inkType: PKInk.InkType
                switch selectedBrush.kind {
                case .pen: inkType = .pen
                case .marker: inkType = .marker
                case .pencil: inkType = .pencil
                }
                let uiColor = UIColor(selectedBrush.color)
                canvas.tool = PKInkingTool(
                    inkType,
                    color: uiColor,
                    width: selectedBrush.width
                )
            }
        }

        class Coordinator: NSObject, PKCanvasViewDelegate {
            var parent: PencilCanvasView
            init(_ parent: PencilCanvasView) { self.parent = parent }
            func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
                parent.data = canvasView.drawing.dataRepresentation()
            }
        }
    }
#endif

#if canImport(UIKit)
    struct NoiseEditSheet: View {
        @Binding var layer: EditorLayer
        @Environment(\.dismiss) private var dismiss
        @State private var intensityPercent: Double = 30  // 0...100
        @State private var previewImage: UIImage?
        @State private var originalData: Data = Data()

        var body: some View {
            NavigationStack {
                VStack(spacing: 16) {
                    Group {
                        if let ui = previewImage {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(radius: 2)
                                .frame(maxHeight: 360)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10).fill(
                                    Color(.secondarySystemBackground)
                                )
                                ProgressView().controlSize(.large)
                            }
                            .frame(height: 240)
                        }
                    }
                    .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Noise").font(.headline)
                            Spacer()
                            Text("\(Int(intensityPercent))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $intensityPercent, in: 0...100, step: 1) {
                            _ in
                            updatePreview()
                        }
                    }
                    .padding(.horizontal, 16)

                    Spacer(minLength: 0)
                }
                .navigationTitle("Noisy Filter")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Apply") {
                            guard
                                let data = applyNoise(
                                    to: originalData,
                                    amount: intensityPercent / 100.0
                                )
                            else {
                                dismiss()
                                return
                            }
                            layer.content = .image(ImageModel(data: data))
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    if case .image(let model) = layer.content {
                        originalData = model.data
                        updatePreview()
                    }
                }
            }
        }

        private func updatePreview() {
            guard !originalData.isEmpty else { return }
            let amt = intensityPercent / 100.0
            if let data = applyNoise(to: originalData, amount: amt),
                let ui = UIImage(data: data)
            {
                previewImage = ui
            }
        }

        private func applyNoise(to data: Data, amount: Double) -> Data? {
            guard let input = UIImage(data: data),
                let cg = input.cgImage
            else { return nil }
            let ciInput = CIImage(cgImage: cg)

            let context = CIContext(options: nil)
            let extent = ciInput.extent

            // Random noise (grayscale)
            let rng = CIFilter.randomGenerator()
            guard let noiseBase = rng.outputImage?.cropped(to: extent) else {
                return nil
            }

            // Desaturate noise to grayscale
            let mono = CIFilter.colorControls()
            mono.inputImage = noiseBase
            mono.saturation = 0
            guard let noiseGray = mono.outputImage else { return nil }

            // Blend noise over the image with overlay blend (grain-like)
            let overlay = CIFilter.overlayBlendMode()
            overlay.inputImage = noiseGray
            overlay.backgroundImage = ciInput
            guard let overlayed = overlay.outputImage else { return nil }

            // Mix original with overlay result by 'amount' using dissolve
            let dissolve = CIFilter.dissolveTransition()
            dissolve.inputImage = ciInput
            dissolve.targetImage = overlayed
            dissolve.time = Float(amount)
            guard let mixed = dissolve.outputImage?.cropped(to: extent) else {
                return nil
            }

            guard let outCG = context.createCGImage(mixed, from: extent) else {
                return nil
            }
            let out = UIImage(
                cgImage: outCG,
                scale: input.scale,
                orientation: input.imageOrientation
            )
            return out.pngData()
        }
    }
#endif

// MARK: - Codable helpers

struct RGBA: Codable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double
}

extension Color {
    func rgba() -> RGBA {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBA(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
        #else
        // Fallback: encode as opaque black if platform doesn't expose components
        return RGBA(r: 0, g: 0, b: 0, a: 1)
        #endif
    }
}

extension RGBA {
    func makeColor() -> Color {
        #if canImport(UIKit)
        return Color(UIColor(red: r, green: g, blue: b, alpha: a))
        #else
        return Color(red: r, green: g, blue: b, opacity: a)
        #endif
    }
}

extension Font.Weight {
    var name: String {
        switch self {
        case .ultraLight: return "ultraLight"
        case .thin: return "thin"
        case .light: return "light"
        case .regular: return "regular"
        case .medium: return "medium"
        case .semibold: return "semibold"
        case .bold: return "bold"
        case .heavy: return "heavy"
        case .black: return "black"
        default: return "regular"
        }
    }

    static func fromName(_ name: String) -> Font.Weight {
        switch name {
        case "ultraLight": return .ultraLight
        case "thin": return .thin
        case "light": return .light
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        case "heavy": return .heavy
        case "black": return .black
        default: return .regular
        }
    }
}
