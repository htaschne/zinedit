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
    @State private var allFontFamilies: [String] = []
    @State private var selectedFontFamily: String = "System"
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
                            Picker("Font", selection: $selectedFontFamily) {
                                Text("System").tag("System")
                                ForEach(allFontFamilies, id: \.self) { family in
                                    Text(family)
                                        .font(
                                            .custom(
                                                postscriptName(
                                                    forFamily: family,
                                                    bold: false,
                                                    italic: false
                                                ) ?? family,
                                                size: 16
                                            )
                                        )
                                        .tag(family)
                                }
                            }
                            .accessibilityIdentifier("fontPicker")
                        } label: {
                            HStack {
                                Text("Font").font(.body).foregroundStyle(
                                    .primary
                                )
                                Spacer()

                                ZStack {
                                    RoundedRectangle(
                                        cornerRadius: 100,
                                        style: .continuous
                                    )
                                    .fill(Color("BrandZinerPrimary15"))
                                    .overlay(
                                        RoundedRectangle(
                                            cornerRadius: 100,
                                            style: .continuous
                                        )
                                        .stroke(Color(.separator), lineWidth: 1)
                                    )

                                    Group {
                                        if selectedFontFamily == "System" {
                                            Text("Default")
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                        } else {
                                            Text(selectedFontFamily)
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .minimumScaleFactor(0.8)
                                    .padding(.horizontal, 12)
                                }
                                .frame(minWidth: 78, minHeight: 34)
                                .fixedSize(horizontal: true, vertical: false)
                                .contentShape(
                                    RoundedRectangle(
                                        cornerRadius: 100,
                                        style: .continuous
                                    )
                                )
                                .accessibilityIdentifier("fontSelectedBadge")
                            }
                            .padding(.vertical, 6)
                            .accessibilityIdentifier("fontMenu")
                        }
                        .tint(.primary)

                        HStack(spacing: 12) {
                            Text("Size \(Int(fontSize))")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()

                            StepperPill(
                                left: "-",
                                right: "+",
                                fontSize: $fontSize
                            )
                            .frame(minHeight: 32)
                        }

                        LabeledContent("Font style") {
                            FontStyleSegmented(
                                isBold: $isBold,
                                isItalic: $isItalic
                            )
                            .accessibilityIdentifier("fontStyleSegmented")
                        }
                        ColorPicker("Color", selection: $color)
                    }
                    Section("Preview") {
                        let font: Font = {
                            if selectedFontFamily == "System" {
                                return .system(
                                    size: fontSize,
                                    weight: isBold ? .bold : .regular
                                )
                            } else {
                                let ps = postscriptName(
                                    forFamily: selectedFontFamily,
                                    bold: isBold,
                                    italic: isItalic
                                )
                                return .custom(
                                    ps ?? selectedFontFamily,
                                    size: fontSize
                                )
                            }
                        }()

                        Group {
                            if selectedFontFamily == "System" && isItalic {
                                Text(text).font(font).italic()
                            } else {
                                Text(text).font(font)
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
                    allFontFamilies = families
                #endif
                if case .text(let t) = layer.content {
                    if let name = t.fontName, !name.isEmpty {
                        #if canImport(UIKit)
                            if let ui = UIFont(name: name, size: 16) {
                                selectedFontFamily = ui.familyName
                            } else {
                                selectedFontFamily = name  // assume it was already a family
                            }
                        #else
                            selectedFontFamily = name
                        #endif
                    } else {
                        selectedFontFamily = "System"
                    }
                    text = t.text
                    fontSize = Double(t.fontSize)
                    isBold = (t.weight == .bold)
                    isItalic = t.isItalic
                    color = t.color
                }
            }
            .accessibilityIdentifier("textEditSheet")
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        onApply?()
                        let chosen =
                            (selectedFontFamily == "System")
                            ? nil : selectedFontFamily
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
            segment(title: "B", active: isBold, italic: false) {
                isBold.toggle()
            }
            separator
            segment(title: "I", active: isItalic, italic: true) {
                isItalic.toggle()
            }
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
    private func segment(
        title: String,
        active: Bool,
        italic: Bool,
        action: @escaping () -> Void
    ) -> some View {
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

#if canImport(UIKit)
    private func postscriptName(
        forFamily family: String,
        bold: Bool,
        italic: Bool
    ) -> String? {
        var traits = UIFontDescriptor.SymbolicTraits()
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let base = UIFontDescriptor(fontAttributes: [.family: family])
        let desc = base.withSymbolicTraits(traits) ?? base
        let font = UIFont(descriptor: desc, size: 16)
        return font.fontName
    }
#else
    private func postscriptName(
        forFamily family: String,
        bold: Bool,
        italic: Bool
    ) -> String? { nil }
#endif

struct StepperPill: View {
    @Binding var fontSize: Double

    var body: some View {
        ZStack {

            RoundedRectangle(
                cornerRadius: 100,
                style: .continuous
            )
            .fill(Color("BrandZinerPrimary15"))
            .overlay(
                RoundedRectangle(
                    cornerRadius: 100,
                    style: .continuous
                )
                .stroke(Color(.separator), lineWidth: 1)
            )

            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    fontSize = max(2, fontSize - 1)
                } label: {
                    Text("-")
                        .font(.headline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color("BrandZinerPrimary15"))
                .accessibilityIdentifier("fontSizeMinus")
                .accessibilityLabel("Decrease font size")

                Button {
                    UIImpactFeedbackGenerator(style: .medium)
                        .impactOccurred()
                    fontSize = min(128, fontSize + 1)
                } label: {
                    Text("+")
                        .font(.headline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color("BrandZinerPrimary15"))
                .accessibilityIdentifier("fontSizePlus")
                .accessibilityLabel("Increase font size")
            }
            .foregroundStyle(.primary)
        }
        .lineLimit(1)
        .truncationMode(.middle)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 12)
    }
}

#Preview("StepperPill") {
    return StepperPill(fontSize: .constant(0))
}
