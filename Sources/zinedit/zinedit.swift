import CoreImage
import CoreImage.CIFilterBuiltins
import PhotosUI
import SwiftUI
import Combine


// Paint support
#if canImport(PencilKit)
    import PencilKit
#endif
#if canImport(UIKit)
    import UIKit
#endif

@MainActor
enum Haptics {
    @MainActor
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

// MARK: - Public API
public struct EditorCanvasView: View {
    @Binding public var layers: [EditorLayer]
    private let config: EditorConfig
    private let onExport: ((UIImage) -> Void)?
    private let onExportPDF: ((Data) -> Void)?
    private let onChange: (([EditorLayer]) -> Void)?
    
    @Binding public var renderedImages: [UIImage]
    @State private var snapshotTrigger: Bool = false

    @StateObject private var model = EditorModel()
    @Environment(\.undoManager) private var undoManager
    @Environment(\.horizontalSizeClass) private var hSizeClass

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
    @State private var isLoadingPhoto: Bool = false

    // Pagination: always 8 pages
    @Binding private var pages: [[EditorLayer]]
    @State private var currentPage: Int = 0

    public init(
        layers: Binding<[EditorLayer]>,
        pages: Binding<[[EditorLayer]]>,
        images: Binding<[UIImage]>,
        config: EditorConfig = .init(),
        onExport: ((UIImage) -> Void)? = nil,
        onExportPDF: ((Data) -> Void)? = nil,
        onChange: (([EditorLayer]) -> Void)? = nil
    ) {
        self._layers = layers
        self.config = config
        self.onExport = onExport
        self.onExportPDF = onExportPDF
        self.onChange = onChange
        self._pages = pages
        self._renderedImages = images
    }

    public init(
        restoredLayers: [EditorLayer],
        images: Binding<[UIImage]>,
        config: EditorConfig = .init(),
        onExport: ((UIImage) -> Void)? = nil,
        onExportPDF: ((Data) -> Void)? = nil,
        onChange: (([EditorLayer]) -> Void)? = nil
    ) {
        self._layers = .constant(restoredLayers)  // one-way binding; use onChange to persist changes
        self._renderedImages = images
        self._pages = .constant(Array(repeating: restoredLayers, count: 8))
        self.config = config
        self.onExport = onExport
        self.onExportPDF = onExportPDF
        self.onChange = onChange
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color("InterfaceFillGraysGray6").ignoresSafeArea()
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        let outer = geo.size
                        let hInset: CGFloat = 16
                        let vInset: CGFloat = 30
                        let inner = CGSize(
                            width: max(0, outer.width - hInset * 2),
                            height: max(0, outer.height - vInset * 2)
                        )
                        let a4Ratio: CGFloat = 297.0 / 210.0  // height / width
                        let canvas: CGSize = {
                            let wFit = inner.width
                            let hFit = inner.height
                            let hFromW = wFit * a4Ratio
                            if hFromW <= hFit {
                                return CGSize(width: wFit, height: hFromW)
                            } else {
                                let wFromH = hFit / a4Ratio
                                return CGSize(width: wFromH, height: hFit)
                            }
                        }()

                        ZStack {
                            // Canvas background color (inside margins)
                            Color("SystemLightDarkSystemBackground")

                            ForEach($model.layers) { $layer in
                                if !layer.isHidden {
                                    LayerView(
                                        layer: $layer,
                                        onBeginInteraction: {
                                            model.registerUndoPoint()
                                        }
                                    )
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
                                                    selectedDrawingBinding =
                                                        $layer
                                                    showDrawingSheet = true
                                                #endif
                                            default:
                                                break
                                            }
                                        }
                                    )
                                    .overlay {
                                        if model.selection == layer.id
                                            && !layer.isHidden
                                        {
                                            SelectionBox()
                                                .allowsHitTesting(false)
                                                .scaleEffect(layer.scale)
                                                .rotationEffect(
                                                    layer.rotation
                                                )
                                                .offset(
                                                    x: layer.position.x,
                                                    y: layer.position.y
                                                )
                                        }
                                    }
                                }
                            }
                            if isLoadingPhoto {
                                ZStack {
                                    Rectangle()
                                        .fill(.ultraThinMaterial)
                                    ProgressView()
                                        .controlSize(.large)
                                        .accessibilityIdentifier("photoLoadingSpinner")
                                }
                                .accessibilityIdentifier("photoLoadingOverlay")
                            }
                        }
                        // Exact canvas size & centered position with margins respected
                        .frame(width: canvas.width, height: canvas.height)
                        .snapshot(snapshotTrigger) { image in
                            if let image = image {
                                // Salva no array de imagens do caller
                                let temp = self.model.selection
                                self.model.selection = nil
                                self.renderedImages[currentPage] = image
                                self.snapshotTrigger.toggle()
                                
                                self.model.selection = temp
                            }
                        }
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                        )
                        .position(x: outer.width / 2, y: outer.height / 2)
                        .accessibilityIdentifier("canvas")
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                        )
                        .onTapGesture { model.selection = nil }
                        .onDrop(
                            of: ["public.image", "public.text"],
                            isTargeted: nil
                        ) { providers in
                            model.handleDrop(providers, in: canvas)
                            return true
                        }
                        .onAppear { canvasSize = canvas }
                        .onChange(of: outer) { _, newOuter in
                            let updatedInner = CGSize(
                                width: max(0, newOuter.width - hInset * 2),
                                height: max(0, newOuter.height - vInset * 2)
                            )
                            let updatedCanvas: CGSize = {
                                let wFit = updatedInner.width
                                let hFit = updatedInner.height
                                let hFromW = wFit * a4Ratio
                                if hFromW <= hFit {
                                    return CGSize(
                                        width: wFit,
                                        height: hFromW
                                    )
                                } else {
                                    let wFromH = hFit / a4Ratio
                                    return CGSize(
                                        width: wFromH,
                                        height: hFit
                                    )
                                }
                            }()
                            canvasSize = updatedCanvas
                        }
                    }

                    // Pagination controls under the canvas
                    HStack(spacing: 8) {
                        Button {
                            Haptics.medium()
                            if currentPage > 0 {
                                pages[currentPage] = model.layers
                                currentPage -= 1
                                model.selection = nil
                                model.layers = pages[currentPage]
                            }
                        } label: {
                            Image(systemName: "arrow.left")
                                .frame(width: 28, height: 28)
                                .foregroundStyle(
                                    currentPage > 0
                                        ? Color("BrandZinerPrimary100")
                                        : Color("InterfaceFillGraysGray6")
                                )
                        }
                        .background(
                            Circle()
                                .fill(
                                    currentPage > 0
                                        ? Color("BrandZinerPrimary15")
                                        : Color("InterfaceFillGraysGray6")
                                )
                        )
                        .disabled(currentPage == 0)
                        .accessibilityIdentifier("pagePrevButton")

                        Text("\(currentPage + 1)")
                            .font(.body.weight(.semibold))
                            .accessibilityIdentifier("pageLabel")
                            .frame(
                                width: 40,
                                height: 22,
                                alignment: .center
                            )

                        Button {
                            Haptics.medium()
                            if currentPage < 7 {
                                pages[currentPage] = model.layers
                                currentPage += 1
                                model.selection = nil
                                model.layers = pages[currentPage]
                            }
                        } label: {
                            Image(systemName: "arrow.right")
                                .frame(width: 28, height: 28)
                                .foregroundStyle(
                                    currentPage < 7
                                        ? Color("BrandZinerPrimary100")
                                        : Color("InterfaceFillGraysGray6")
                                )
                        }
                        .background(
                            Circle()
                                .fill(
                                    currentPage < 7
                                        ? Color("BrandZinerPrimary15")
                                        : Color("InterfaceFillGraysGray6")
                                )
                        )
                        .disabled(currentPage == 7)
                        .accessibilityIdentifier("pageNextButton")
                    }
                    .padding(.horizontal, 16)
                }
            }
            .background(Color(.white))
            .onDisappear() {
                Task {
                    @MainActor in
                        var images: [UIImage] = []
                        for page in pages {
                            let img = await snapshotOfPage(page)
                            images.append(img)
                        }
                        self.renderedImages = images
                    }
            }
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task {
                            @MainActor in
                                var images: [UIImage] = []
                                for page in pages {
                                    let img = await snapshotOfPage(page)
                                    images.append(img)
                                }
                                self.renderedImages = images
                            }
                        Haptics.medium()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityIdentifier("undoTopButton")
                }
                
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        Haptics.medium()
                        model.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!model.canUndo)
                    .accessibilityIdentifier("undoTopButton")

                    Button {
                        Haptics.medium()
                        model.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!model.canRedo)
                    .accessibilityIdentifier("redoTopButton")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Haptics.medium()
                        exportAllPages()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                    .accessibilityIdentifier("shareButton")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        Haptics.medium()
                        model.addText()
                        if let id = model.selection,
                            let binding = bindingForLayer(id)
                        {
                            binding.position.wrappedValue = .zero
                            selectedTextBinding = binding
                            showTextSheet = true
                        }
                    } label: {
                        Label("Text", systemImage: "textformat")
                    }
                    .accessibilityIdentifier("textButton")
                    if config.showsPhotosPicker {
                        PhotosPicker(
                            selection: $model.photoSelection,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label("Image", systemImage: "photo.badge.plus")
                        }
                        .accessibilityIdentifier("imageButton")
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                Haptics.medium()
                            }
                        )
                    }
                    #if canImport(PencilKit)
                        if config.paint != nil {
                            Button {
                                Haptics.medium()
                                model.addDrawing(baseSize: canvasSize)
                                if let id = model.selection,
                                    let binding = bindingForLayer(id)
                                {
                                    binding.position.wrappedValue = .zero
                                    selectedDrawingBinding = binding
                                    showDrawingSheet = true
                                }
                            } label: {
                                Label("Paint", systemImage: "pencil.tip")
                            }
                            .accessibilityIdentifier("paintButton")
                        }
                    #endif
                    Spacer()

                    Button {
                        Haptics.medium()
                        showLayersSheet = true
                    } label: {
                        Label("Layers", systemImage: "square.3.layers.3d")
                    }
                    .disabled(!model.canLayer)
                    .accessibilityIdentifier("layersButton")

                    // Keep Trash visible when there is a selection
                    if model.selection != nil {
                        Button(role: .destructive) {
                            Haptics.medium()
                            model.deleteSelected()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .accessibilityIdentifier("deleteButton")
                    }

                    // Only show Noise in More menu, and only for selected image layers
                    if let id = model.selection,
                        let index = model.indexOfLayer(id),
                        case .image = model.layers[index].content
                    {
                        Menu {
                            Button {
                                Haptics.medium()
                                if let binding = bindingForLayer(id) {
                                    selectedImageBinding = binding
                                    showNoiseSheet = true
                                }
                            } label: {
                                Label(
                                    "Noise…",
                                    systemImage: "slider.horizontal.3"
                                )
                            }
                            .accessibilityIdentifier("noiseMenuItem")
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                        .accessibilityIdentifier("moreMenuButton")
                    }
                }
            })
            .sheet(isPresented: $showTextSheet) {
                if let $layer = selectedTextBinding {
                    TextEditSheet(
                        layer: $layer,
                        show: $showTextSheet,
                        onApply: { model.registerUndoPoint() },
                    )
                }
            }
            #if canImport(PencilKit)
                .sheet(isPresented: $showDrawingSheet) {
                    if let $layer = selectedDrawingBinding,
                        let paint = config.paint
                    {
                        DrawingEditSheet(
                            layer: $layer,
                            config: paint,
                            onApply: { model.registerUndoPoint() }
                        )
                    }
                }
            #endif
            .sheet(isPresented: $showNoiseSheet) {
                if let $layer = selectedImageBinding {
                    NoiseEditSheet(
                        layer: $layer,
                        onApply: { model.registerUndoPoint() }
                    )
                }
            }
            .sheet(isPresented: $showLayersSheet) {
                LayersSheet(
                    layers: $model.layers,
                    selection: $model.selection,
                    onChange: { model.registerUndoPoint() }
                )
                .presentationDetents([.fraction(0.5), .large])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: model.photoSelection) { _, _ in
                isLoadingPhoto = true
                Task { @MainActor in
                    await model.loadSelectedPhoto()
                    if let id = model.selection,
                        let binding = bindingForLayer(id)
                    {
                        binding.position.wrappedValue = .zero
                    }
                    isLoadingPhoto = false
                }
            }
            // keep EditorModel and host binding in sync
            .onAppear {
                // seed page 0 from host binding on first appear
                if pages[0].isEmpty && !layers.isEmpty {
                    pages[0] = layers
                }
                model.layers = pages[currentPage]
            }
            .onChange(of: model.layers) { _, newValue in
                pages[currentPage] = newValue
                handleUpdate()
                self.layers = newValue  // keep host in sync with the current page
                //var newImages: [UIImage] = []
                    
                    // 2. Iterate through all pages (the 'pages' binding holds [[EditorLayer]])
                    for pageLayers in pages {
                        
                        
                        // 3. Render each page using the specific Zine render logic
                        // We use the config.exportSize to ensure high resolution (e.g. 1080x1920)
                        // rather than the screen size.
//                        let image = EditorRenderer.renderImage(
//                            layers: pageLayers,
//                            size: config.exportSize
//                        )
                        //let img = SnapshotRenderer.render(pageView, size: config.exportSize)
                        //newImages.append(img)
                        
                        
                        
                    }
                    
                    // 4. Update the binding so the parent View (EditorView) receives the images
                    //self.renderedImages = newImages
                    
                    // Optional: Print debug info
                    //print("onDisappear: Rendered \(newImages.count) pages.")
                self.onChange?(newValue)
            }
            .onChange(of: showDrawingSheet) {_, newValue in
                if newValue == false {
                    handleUpdate()
                }
            }
            .onChange(of: showTextSheet) {_, newValue in
                    handleUpdate()
            }
            .onChange(of: layers) { oldValue, newValue in
                if model.layers != newValue {
                    model.layers = newValue
                }
                pages[currentPage] = newValue
            }
            
        }

    }

    private func bindingForLayer(_ id: UUID) -> Binding<EditorLayer>? {
        guard let index = model.indexOfLayer(id) else { return nil }
        return $model.layers[index]
    }
    
    private func handleUpdate() {
        
        let newValue = model.layers

            pages[currentPage] = newValue
            self.layers = newValue

            // só dispara depois de atualizar layers e páginas
            //snapshotTrigger.toggle()
        
            
        for page in pages {
            Task {
                await snapshotOfPage(page)
            }
        }
            self.onChange?(newValue)
        
//        let newValue = model.layers
//
//        pages[currentPage] = newValue
//        self.layers = newValue
//
//        var newImages: [UIImage] = []
//
//        for pageLayers in pages {
//            let image = EditorRenderer.renderImage(
//                layers: pageLayers,
//                size: config.exportSize
//            )
//            newImages.append(image)
//        }
//
//        self.renderedImages = newImages
//        self.onChange?(newValue)
    }
    
    private func snapshotOfPage(_ pageLayers: [EditorLayer]) async -> UIImage {
        await withCheckedContinuation { continuation in
            
            var trigger = true
            
            let view = EditorCanvasSnapshotView(
                layers: pageLayers,
                canvasSize: config.exportSize,
                selection: nil
            )
            .snapshot(trigger) { image in
                continuation.resume(returning: image ?? UIImage())
            }

            // Mount offscreen
            let host = UIHostingController(rootView: view)
            host.view.frame = CGRect(origin: .zero, size: config.exportSize)

            let window = UIWindow(frame: host.view.frame)
            window.rootViewController = host
            window.isHidden = false

            // trigger snapshot
           trigger.toggle()
        }
    }

    private func export() {
        let image = EditorRenderer.renderImage(
            layers: model.layers,
            size: config.exportSize
        )
        onExport?(image)
    }

    private func exportAllPages() {
        let rect = CGRect(origin: .zero, size: config.exportSize)
        let renderer = UIGraphicsPDFRenderer(bounds: rect)
        let data = renderer.pdfData { ctx in
            for i in 0..<8 {
                ctx.beginPage()
                let img = EditorRenderer.renderImage(
                    layers: pages[i],
                    size: config.exportSize
                )
                img.draw(in: rect)
            }
        }
        // Prefer PDF export for printer workflows
        onExportPDF?(data)
        // Also provide current page image via legacy callback if needed
        if let onExport = onExport {
            let current = EditorRenderer.renderImage(
                layers: pages[currentPage],
                size: config.exportSize
            )
            onExport(current)
        }
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
                    Color.white
                    ForEach(layers.filter { !$0.isHidden }) { layer in
                        LayerRenderView(layer: layer)
                    }
                }
                .frame(width: size.width, height: size.height)
        )
        
        renderer.scale = 5.0
        
        return renderer.uiImage ?? UIImage()
    }
}

struct SnapshotRenderer {
    @MainActor
    static func render<V: View>(_ view: V, size: CGSize) -> UIImage {
        let controller = UIHostingController(rootView:
            view
                .frame(width: size.width, height: size.height)
        )
        
        let targetSize = controller.view.intrinsicContentSize
        controller.view.bounds = CGRect(origin: .zero, size: targetSize)
        controller.view.backgroundColor = .clear
        
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        
        return renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
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
        position: CGPoint = .zero, /*CGPoint(x: 150, y: 150),*/
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
    private enum CodingKeys: String, CodingKey {
        case id, content, position, scale, rotationDegrees, isHidden
    }

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
    private enum CodingKeys: String, CodingKey {
        case type, text, image, drawing
    }
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
            let value = try container.decode(
                DrawingModel.self,
                forKey: .drawing
            )
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
    public var fontName: String?
    public var isItalic: Bool

    public init(
        text: String,
        fontSize: CGFloat = 28,
        color: Color = .primary,
        weight: Font.Weight = .regular,
        fontName: String? = nil,
        isItalic: Bool = false
    ) {
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.weight = weight
        self.fontName = fontName
        self.isItalic = isItalic
    }
}

extension TextModel {
    private enum CodingKeys: String, CodingKey {
        case text, fontSize, color, weight, fontName, isItalic
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try c.decode(String.self, forKey: .text)
        self.fontSize = try c.decode(CGFloat.self, forKey: .fontSize)
        let rgba = try c.decode(RGBA.self, forKey: .color)
        self.color = rgba.makeColor()
        let w = try c.decode(String.self, forKey: .weight)
        self.weight = Font.Weight.fromName(w)
        self.fontName = try c.decodeIfPresent(String.self, forKey: .fontName)
        self.isItalic =
            try c.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encode(fontSize, forKey: .fontSize)
        try c.encode(color.rgba(), forKey: .color)
        try c.encode(weight.name, forKey: .weight)
        try c.encodeIfPresent(fontName, forKey: .fontName)
        try c.encode(isItalic, forKey: .isItalic)
    }
}

public struct ImageModel: Equatable, Codable {
    public var data: Data
    public init(data: Data) { self.data = data }
}

// MARK: - Preview
#Preview {
    PreviewHost(images: [])
}

struct PreviewHost: View {
    @State var layers: [EditorLayer] = []
    @State var pages: [[EditorLayer]] = Array(repeating: [], count: 8)
    @State var images: [UIImage]
    var body: some View {
        EditorCanvasView(layers: $layers, pages: $pages, images: $images)
    }
}

struct LayersSheet: View {
    @Binding var layers: [EditorLayer]
    @Binding var selection: UUID?
    @Environment(\.dismiss) private var dismiss
    var onChange: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(layers.indices).reversed(), id: \.self) { idx in
                    let layer = layers[idx]
                    HStack(spacing: 12) {
                        LayerRowThumb(layer: layer)
                            .frame(width: 44, height: 44)
                        Text(title(for: layer))
                            .lineLimit(1)
                            .foregroundStyle(
                                selection == layer.id ? .primary : .secondary
                            )
                        Spacer()
                        Button {
                            #if canImport(UIKit)
                                Haptics.medium()
                            #endif
                            onChange?()
                            layers[idx].isHidden.toggle()
                            if layers[idx].isHidden, selection == layer.id {
                                selection = nil
                            }
                        } label: {
                            Image(
                                systemName: layers[idx].isHidden
                                    ? "eye.slash" : "eye"
                            )
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            layers[idx].isHidden ? "Show layer" : "Hide layer"
                        )
                        .accessibilityIdentifier("visibilityButton-\(idx)")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = layer.id }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            #if canImport(UIKit)
                                Haptics.medium()
                            #endif
                            onChange?()
                            layers[idx].isHidden.toggle()
                            if layers[idx].isHidden, selection == layer.id {
                                selection = nil
                            }
                        } label: {
                            if layers[idx].isHidden {
                                Label("Show", systemImage: "eye.slash")
                            } else {
                                Label("Hide", systemImage: "eye")
                            }
                        }
                    }
                    .accessibilityIdentifier("layerRow-\(idx)")
                }
                .onMove(perform: move)
            }
            .accessibilityIdentifier("layersList")
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        #if canImport(UIKit)
                            Haptics.medium()
                        #endif
                        dismiss()
                    }
                    .accessibilityIdentifier("layersDoneButton")
                }
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        let count = layers.count
        // Map displayed (reversed) indices to the original array indices.
        let mappedSource = IndexSet(source.map { count - 1 - $0 })
        let mappedDestination = count - destination
        layers.move(fromOffsets: mappedSource, toOffset: mappedDestination)
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
                        let rect = CGRect(
                            origin: .zero,
                            size: drawingModel.size
                        )
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
                let base = Text(t.text)
                    .foregroundStyle(t.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    .padding(4)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .center
                    )
                    .background(.thinMaterial)

                if let name = t.fontName, !name.isEmpty {
                    base
                        .font(.custom(name, size: 12))
                } else {
                    base
                        .font(.system(size: 12, weight: t.weight))
                }
            }
        }
        .frame(width: 44, height: 44)
        .clipped()
        .opacity(layer.isHidden ? 0.35 : 1)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(
                Color(.separator),
                lineWidth: 1
            )
        )
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
        @State private var brushColor: Color = .black
        @State private var brushWidth: CGFloat = 3
        @State private var showWidthPopover: Bool = false
        var onApply: (() -> Void)? = nil

        private var baseSize: CGSize {
            if case .drawing(let m) = layer.content { return m.size }
            return CGSize(width: 1080, height: 1920)
        }

        var body: some View {
            NavigationStack {
                VStack(spacing: 12) {
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
                    .accessibilityIdentifier("drawingCanvas")
                }
                .accessibilityIdentifier("drawingEditSheet")
                .toolbar(content: {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Apply") {
                            Haptics.medium()
                            onApply?()
                            layer.content = .drawing(
                                DrawingModel(data: data, size: baseSize)
                            )
                            dismiss()
                        }
                        .accessibilityIdentifier("applyDrawingButton")
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            Haptics.medium()
                            dismiss()
                        }
                        .accessibilityIdentifier("cancelDrawingButton")
                    }

                    // Bottom toolbar — mimic EditorCanvasView: 3 left, Spacer, 3 right
                    ToolbarItemGroup(placement: .bottomBar) {
                        // LEFT: three brushes
                        Button {
                            selectBrush(idxFine)
                        } label: {
                            Image(systemName: "pencil")
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .foregroundStyle((selectedBrushIndex == idxFine && !erasing) ? Color("BrandZinerPrimary100") : .secondary)
                        .accessibilityIdentifier("brushFineButton")

                        Button {
                            selectBrush(idxMarker)
                        } label: {
                            Image(systemName: "paintbrush.pointed")
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .foregroundStyle((selectedBrushIndex == idxMarker && !erasing) ? Color("BrandZinerPrimary100") : .secondary)
                        .accessibilityIdentifier("brushMarkerButton")

                        Button {
                            selectBrush(idxSketch)
                        } label: {
                            Image(systemName: "paintbrush")
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .foregroundStyle((selectedBrushIndex == idxSketch && !erasing) ? Color("BrandZinerPrimary100") : .secondary)
                        .accessibilityIdentifier("brushSketchButton")

                        Spacer()

                        // RIGHT: color, width, eraser
                        // Color (paintpalette) — overlay a ColorPicker to use system UI while keeping our icon
                        ZStack {
                            Button {
                                Haptics.medium()
                            } label: {
                                Image(systemName: "paintpalette")
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .foregroundStyle(brushColor)
                            .accessibilityIdentifier("brushColorButton")

                            ColorPicker("", selection: $brushColor, supportsOpacity: true)
                                .labelsHidden()
                                .frame(width: 24, height: 24)
                                .opacity(0.02)
                                .allowsHitTesting(true)
                                .simultaneousGesture(
                                    TapGesture().onEnded { Haptics.medium() }
                                )
                        }

                        // Width (scribble.variable) — popover slider
                        Button {
                            Haptics.medium()
                            showWidthPopover.toggle()
                        } label: {
                            Image(systemName: "scribble.variable")
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("brushWidthButton")
                        .popover(isPresented: $showWidthPopover, attachmentAnchor: .point(.center), arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Stroke").font(.headline)
                                    Spacer()
                                    Text("\(Int(brushWidth)) pt")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                Slider(value: $brushWidth, in: 1...40, step: 1)
                                    .accessibilityIdentifier("brushWidthSlider")
                                    .accentColor(Color("BrandZinerPrimary100"))
                            }
                            .padding(16)
                            .presentationDetents([.height(100)])
                            .presentationCompactAdaptation(.sheet)
                        }

                        // Eraser (kept far right)
                        Button {
                            Haptics.medium()
                            erasing.toggle()
                        } label: {
                            Image(systemName: "eraser")
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .foregroundStyle(erasing ? Color("BrandZinerPrimary100") : .secondary)
                        .accessibilityIdentifier("eraserButton")
                    }
                })
                .onAppear {
                    if case .drawing(let m) = layer.content { self.data = m.data }
                    if config.brushes.indices.contains(selectedBrushIndex) {
                        let base = config.brushes[selectedBrushIndex]
                        brushColor = base.color
                        brushWidth = base.width
                    } else if let base = config.brushes.first {
                        brushColor = base.color
                        brushWidth = base.width
                    }
                }
                .onChange(of: selectedBrushIndex) { _, _ in
                    if config.brushes.indices.contains(selectedBrushIndex) {
                        let base = config.brushes[selectedBrushIndex]
                        brushColor = base.color
                        brushWidth = base.width
                    }
                }
            }
        }

        private var safeSelectedBrush: EditorBrush {
            if config.brushes.indices.contains(selectedBrushIndex) {
                let base = config.brushes[selectedBrushIndex]
                return EditorBrush(kind: base.kind, name: base.name, color: brushColor, width: brushWidth)
            }
            return EditorBrush(kind: .pen, name: "Pen", color: brushColor, width: brushWidth)
        }

        // MARK: - Brush helpers (by name with sensible fallbacks)
        private var idxFine: Int {
            indexForBrush(named: "fine") ?? 0
        }
        private var idxMarker: Int {
            if let i = indexForBrush(named: "marker") { return i }
            return min(1, max(0, config.brushes.count - 1))
        }
        private var idxSketch: Int {
            if let i = indexForBrush(named: "sketch") { return i }
            return min(2, max(0, config.brushes.count - 1))
        }
        private func indexForBrush(named name: String) -> Int? {
            config.brushes.firstIndex { $0.name.lowercased() == name.lowercased() }
        }
        private func selectBrush(_ idx: Int) {
            guard config.brushes.indices.contains(idx) else { return }
            Haptics.medium()
            selectedBrushIndex = idx
            erasing = false
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
        var onApply: (() -> Void)? = nil

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
                        .accessibilityIdentifier("noiseSlider")
                    }
                    .padding(.horizontal, 16)

                    Spacer(minLength: 0)
                }
                .accessibilityIdentifier("noiseEditSheet")
                .navigationTitle("Noisy Filter")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            Haptics.medium()
                            dismiss()
                        }
                        .accessibilityIdentifier("cancelNoiseButton")
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Apply") {
                            Haptics.medium()
                            guard
                                let data = applyNoise(
                                    to: originalData,
                                    amount: intensityPercent / 100.0
                                )
                            else {
                                dismiss()
                                return
                            }
                            onApply?()
                            layer.content = .image(ImageModel(data: data))
                            dismiss()
                        }
                        .accessibilityIdentifier("applyNoiseButton")
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
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
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
    
