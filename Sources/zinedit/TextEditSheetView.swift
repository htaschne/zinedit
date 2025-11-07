//
//  TextEditSheet.swift
//  zinedit
//
//  Created by Agatha Schneider on 07/11/25.
//

import SwiftUI

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
                        Stepper(
                            "Font size \(Int(fontSize))",
                            value: $fontSize,
                            in: 12...128
                        )
                        Toggle("Bold", isOn: $isBold)
                        ColorPicker("Color", selection: $color)
                    }
                    Section("Preview") {
                        Text(text)
                            .font(
                                .system(
                                    size: fontSize,
                                    weight: isBold ? .bold : .regular
                                )
                            )
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
                        layer.content = .text(
                            TextModel(
                                text: text,
                                fontSize: CGFloat(fontSize),
                                color: color,
                                weight: isBold
                                    ? Font.Weight.bold : Font.Weight.regular
                            )
                        )
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
