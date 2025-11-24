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
                        Stepper(
                            "Font size \(Int(fontSize))",
                            value: $fontSize,
                            in: 12...128
                        )
                        Toggle("Bold", isOn: $isBold)
                        ColorPicker("Color", selection: $color)
                    }
                    Section("Font") {
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
                    }
                    Section("Preview") {
                        Text(text)
                            .font(selectedFontName == "System"
                                  ? .system(size: fontSize, weight: isBold ? .bold : .regular)
                                  : .custom(selectedFontName, size: fontSize))
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
                                fontName: chosen
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
