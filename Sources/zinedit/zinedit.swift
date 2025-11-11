// Paint support
#if canImport(PencilKit)
import PencilKit
#endif
import SwiftUI
import PhotosUI

// MARK: - Public API
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

public struct EditorConfig: Equatable {
    public var exportSize: CGSize
    public var showsPhotosPicker: Bool
    public var paint: PaintConfig?     // nil disables paint features

    public init(exportSize: CGSize = CGSize(width: 1080, height: 1920),
                showsPhotosPicker: Bool = true,
                paint: PaintConfig? = nil) {
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
    public var brushes: [EditorBrush]          // recommend exactly 3
    public var eraser: EraserMode
    public var allowsFingerDrawing: Bool
    public var showsAppleToolPicker: Bool

    public init(brushes: [EditorBrush],
                eraser: EraserMode = .vector,
                allowsFingerDrawing: Bool = true,
                showsAppleToolPicker: Bool = false) {
        self.brushes = brushes
        self.eraser = eraser
        self.allowsFingerDrawing = allowsFingerDrawing
        self.showsAppleToolPicker = showsAppleToolPicker
    }
}

/// Vector drawing payload compatible with PencilKit's PKDrawing via `dataRepresentation()`.
/// Store `size` as the base canvas size for accurate scaling during export.
public struct DrawingModel: Equatable {
    public var data: Data
    public var size: CGSize

    public init(data: Data, size: CGSize) {
        self.data = data
        self.size = size
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
    case drawing(DrawingModel)
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
