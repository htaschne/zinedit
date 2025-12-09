import SwiftUI

extension View {
    func snapshot(_ trigger: Bool, completion: @escaping (UIImage?) -> Void) -> some View {
        self.modifier(SnapshotModifier(trigger: trigger, onComplete: completion))
    }
}

fileprivate struct SnapshotModifier: ViewModifier {
    let trigger: Bool
    let onComplete: (UIImage?) -> Void
    
    @State private var view: UIView = .init(frame: .zero)

    func body(content: Content) -> some View {
        content
            .background(ViewExtractor(view: view))
            .compositingGroup()
            .onChange(of: trigger) { _, newValue in
                if newValue { generateSnapshot() }
            }
    }
    
    private func generateSnapshot() {
        guard let root = view.superview?.superview else {
            onComplete(nil)
            return
        }

        let renderer = UIGraphicsImageRenderer(bounds: root.bounds)
        let image = renderer.image { context in
            root.drawHierarchy(in: root.bounds, afterScreenUpdates: true)
        }
        
        onComplete(image)
    }
}

fileprivate struct ViewExtractor: UIViewRepresentable {
    
    var view: UIView
    func makeUIView(context: Context) -> some UIView {
        view.backgroundColor = .clear
        return view
    }
    
    func updateUIView(_ uiView: UIViewType, context: Context) {
        
    }
    
}
