//
//  TextEditSheet.swift
//  zinedit
//
//  Created by Agatha Schneider on 07/11/25.
//


import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct TextEditSheet: View {
    @Binding var layer: EditorLayer
    @State private var text: String = ""
    @State private var fontSize: Double = 28
    @State private var isBold = true
    @State private var isItalic = false
    @State private var color: Color = .primary
    var onApply: (() -> Void)? = nil
    @State private var allFontNames: [String] = []
    @State private var selectedFontName: String = "System"
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
                        Menu {
                            Picker("Font", selection: $selectedFontName) {
                                Text("System").tag("System")
                                ForEach(allFontNames, id: \.self) { name in
                                    Text(name).font(.custom(name, size: 16)).tag(name)
                                }
                            }
                            .accessibilityIdentifier("fontPicker")
                        } label: {
                            HStack {
                                if selectedFontName == "System" {
                                    Text("System")
                                } else {
                                    Text(selectedFontName)
                                        .font(.custom(selectedFontName, size: 16))
                                }
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                            .accessibilityIdentifier("fontMenu")
                        }

                        Stepper(
                            "Font size \(Int(fontSize))",
                            value: $fontSize,
                            in: 2...128
                        )
                        LabeledContent("Font style") {
                            FontStyleSegmented(isBold: $isBold, isItalic: $isItalic)
                                .accessibilityIdentifier("fontStyleSegmented")
                        }
                        ColorPicker("Color", selection: $color)
                    }
                    Section("Preview") {
                        let baseFont: Font = (selectedFontName == "System")
                            ? .system(size: fontSize, weight: isBold ? .bold : .regular)
                            : .custom(selectedFontName, size: fontSize)

                        Group {
                            if isItalic {
                                Text(text)
                                    .font(baseFont)
                                    .italic()
                            } else {
                                Text(text)
                                    .font(baseFont)
                            }
                        }
                        .foregroundStyle(color)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                    }
                }
            }
            .onAppear {
                #if canImport(UIKit)
                let families = UIFont.familyNames.sorted()
                allFontNames = families.flatMap { UIFont.fontNames(forFamilyName: $0) }.sorted()
                #endif
                if case .text(let t) = layer.content {
                    selectedFontName = t.fontName ?? "System"
                }
            }
            .accessibilityIdentifier("textEditSheet")
            .navigationTitle("Edit Text")
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        onApply?()
                        let chosen = (selectedFontName == "System") ? nil : selectedFontName
                        layer.content = .text(
                            TextModel(
                                text: text,
                                fontSize: CGFloat(fontSize),
                                color: color,
                                weight: isBold ? .bold : .regular,
                                fontName: chosen,
                                isItalic: isItalic
                            )
                        )
                        dismiss()
                    }
                    .accessibilityIdentifier("applyTextButton")
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("cancelTextButton")
                }
            })
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// Segmented control for Bold / Italic styled like a capsule with dividers.
private struct FontStyleSegmented: View {
    @Binding var isBold: Bool
    @Binding var isItalic: Bool

    var body: some View {
        HStack(spacing: 0) {
            segment(title: "B", active: isBold, italic: false) { isBold.toggle() }
            separator
            segment(title: "I", active: isItalic, italic: true) { isItalic.toggle() }
        }
        .padding(2)
        .background(Color(.systemGray6))
        .clipShape(Capsule())
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 1, height: 20)
            .padding(.vertical, 4)
    }

    @ViewBuilder
    private func segment(title: String, active: Bool, italic: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            let label = Text(title)
                .font(.headline)
            Group {
                if italic {
                    label.italic()
                } else {
                    label
                }
            }
            .frame(minWidth: 36, minHeight: 40)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? .primary : .secondary)
        .background(active ? Color(.systemGray4) : .clear)
    }
}
