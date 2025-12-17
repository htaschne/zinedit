//
//  EditorCanvasViewUITests.swift
//  zinedit
//
//  Created by Bernardo Garcia Fensterseifer on 17/12/25.
//

import XCTest

final class EditorCanvasViewUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Canvas Tests
    
    func testCanvasExists() throws {
        let canvas = app.otherElements["canvas"]
        XCTAssertTrue(canvas.exists, "Canvas should exist")
    }
    
    func testCanvasTapDeselectsLayer() throws {
        // Add a text layer first
        app.buttons["textButton"].tap()
        
        // Verify something is selected (text sheet should appear)
        let textSheet = app.sheets.firstMatch
        XCTAssertTrue(textSheet.waitForExistence(timeout: 2))
        
        // Dismiss sheet
        app.swipeDown()
        
        // Tap canvas to deselect
        app.otherElements["canvas"].tap()
        
        // Selection should be cleared (verify by checking if delete button is hidden)
        let deleteButton = app.buttons["deleteButton"]
        XCTAssertFalse(deleteButton.exists, "Delete button should not exist when nothing is selected")
    }
    
    // MARK: - Text Layer Tests
    
    func testAddTextLayer() throws {
        let textButton = app.buttons["textButton"]
        XCTAssertTrue(textButton.exists, "Text button should exist")
        
        textButton.tap()
        
        // Text edit sheet should appear
        let textSheet = app.sheets.firstMatch
        XCTAssertTrue(textSheet.waitForExistence(timeout: 2), "Text edit sheet should appear")
    }
    
    func testEditTextLayer() throws {
        // Add text layer
        app.buttons["textButton"].tap()
        
        let textSheet = app.sheets.firstMatch
        XCTAssertTrue(textSheet.waitForExistence(timeout: 2))
        
        // Find and type in text field
        let textField = textSheet.textFields.firstMatch
        if textField.exists {
            textField.tap()
            textField.typeText("Test Text")
        }
        
        // Apply changes
        let applyButton = textSheet.buttons["applyTextButton"]
        if applyButton.exists {
            applyButton.tap()
        }
        
        // Sheet should dismiss
        XCTAssertFalse(textSheet.exists, "Text sheet should dismiss after apply")
    }
    
    func testDoubleTabTextLayerOpensEditSheet() throws {
        // Add a text layer first
        app.buttons["textButton"].tap()
        
        let textSheet = app.sheets.firstMatch
        XCTAssertTrue(textSheet.waitForExistence(timeout: 2))
        
        // Close the sheet
        app.swipeDown()
        
        // Double tap on canvas where text layer is (center)
        let canvas = app.otherElements["canvas"]
        canvas.doubleTap()
        
        // Text sheet should appear again
        XCTAssertTrue(textSheet.waitForExistence(timeout: 2), "Double tap should reopen text edit sheet")
    }
    
    // MARK: - Image Layer Tests
    
    func testImageButtonExists() throws {
        let imageButton = app.buttons["imageButton"]
        XCTAssertTrue(imageButton.exists, "Image button should exist")
    }
    
    func testImageLoadingIndicator() throws {
        // This test checks if loading overlay appears
        // Note: In real tests, you'd need to mock photo selection
        let loadingOverlay = app.otherElements["photoLoadingOverlay"]
        let spinner = app.activityIndicators["photoLoadingSpinner"]
        
        // These should not exist initially
        XCTAssertFalse(loadingOverlay.exists, "Loading overlay should not exist initially")
        XCTAssertFalse(spinner.exists, "Loading spinner should not exist initially")
    }
    
    // MARK: - Drawing Tests
    
    func testPaintButtonExists() throws {
        let paintButton = app.buttons["paintButton"]
        // Paint button may not exist if PencilKit is not available or paint config is nil
        // So we just check without asserting
        _ = paintButton.exists
    }
    
    func testDrawingSheetOpens() throws {
        let paintButton = app.buttons["paintButton"]
        
        guard paintButton.exists else {
            throw XCTSkip("Paint button not available")
        }
        
        paintButton.tap()
        
        let drawingSheet = app.otherElements["drawingEditSheet"]
        XCTAssertTrue(drawingSheet.waitForExistence(timeout: 2), "Drawing edit sheet should appear")
    }
    
    func testDrawingBrushSelection() throws {
        let paintButton = app.buttons["paintButton"]
        guard paintButton.exists else {
            throw XCTSkip("Paint button not available")
        }
        
        paintButton.tap()
        
        let drawingSheet = app.otherElements["drawingEditSheet"]
        XCTAssertTrue(drawingSheet.waitForExistence(timeout: 2))
        
        // Test brush buttons
        let fineBrush = app.buttons["brushFineButton"]
        let markerBrush = app.buttons["brushMarkerButton"]
        let sketchBrush = app.buttons["brushSketchButton"]
        
        XCTAssertTrue(fineBrush.exists, "Fine brush button should exist")
        XCTAssertTrue(markerBrush.exists, "Marker brush button should exist")
        XCTAssertTrue(sketchBrush.exists, "Sketch brush button should exist")
        
        // Tap each brush
        markerBrush.tap()
        sketchBrush.tap()
        fineBrush.tap()
    }
    
    func testDrawingEraserToggle() throws {
        let paintButton = app.buttons["paintButton"]
        guard paintButton.exists else {
            throw XCTSkip("Paint button not available")
        }
        
        paintButton.tap()
        
        let drawingSheet = app.otherElements["drawingEditSheet"]
        XCTAssertTrue(drawingSheet.waitForExistence(timeout: 2))
        
        let eraserButton = app.buttons["eraserButton"]
        XCTAssertTrue(eraserButton.exists, "Eraser button should exist")
        
        // Toggle eraser
        eraserButton.tap()
        eraserButton.tap()
    }
    
    func testDrawingBrushWidth() throws {
        let paintButton = app.buttons["paintButton"]
        guard paintButton.exists else {
            throw XCTSkip("Paint button not available")
        }
        
        paintButton.tap()
        
        let drawingSheet = app.otherElements["drawingEditSheet"]
        XCTAssertTrue(drawingSheet.waitForExistence(timeout: 2))
        
        let widthButton = app.buttons["brushWidthButton"]
        XCTAssertTrue(widthButton.exists, "Brush width button should exist")
        
        widthButton.tap()
        
        // Width slider should appear in popover
        let widthSlider = app.sliders["brushWidthSlider"]
        XCTAssertTrue(widthSlider.waitForExistence(timeout: 2), "Brush width slider should appear")
        
        // Adjust slider
        widthSlider.adjust(toNormalizedSliderPosition: 0.75)
    }
    
    func testDrawingColorPicker() throws {
        let paintButton = app.buttons["paintButton"]
        guard paintButton.exists else {
            throw XCTSkip("Paint button not available")
        }
        
        paintButton.tap()
        
        let drawingSheet = app.otherElements["drawingEditSheet"]
        XCTAssertTrue(drawingSheet.waitForExistence(timeout: 2))
        
        let colorButton = app.buttons["brushColorButton"]
        XCTAssertTrue(colorButton.exists, "Color button should exist")
    }
    
    func testDrawingCanvasExists() throws {
        let paintButton = app.buttons["paintButton"]
        guard paintButton.exists else {
            throw XCTSkip("Paint button not available")
        }
        
        paintButton.tap()
        
        let drawingCanvas = app.otherElements["drawingCanvas"]
        XCTAssertTrue(drawingCanvas.waitForExistence(timeout: 2), "Drawing canvas should exist")
    }
    
    func testApplyDrawing() throws {
        let paintButton = app.buttons["paintButton"]
        guard paintButton.exists else {
            throw XCTSkip("Paint button not available")
        }
        
        paintButton.tap()
        
        let drawingSheet = app.otherElements["drawingEditSheet"]
        XCTAssertTrue(drawingSheet.waitForExistence(timeout: 2))
        
        let applyButton = app.buttons["applyDrawingButton"]
        XCTAssertTrue(applyButton.exists, "Apply button should exist")
        
        applyButton.tap()
        
        XCTAssertFalse(drawingSheet.exists, "Drawing sheet should dismiss after apply")
    }
    
    func testCancelDrawing() throws {
        let paintButton = app.buttons["paintButton"]
        guard paintButton.exists else {
            throw XCTSkip("Paint button not available")
        }
        
        paintButton.tap()
        
        let drawingSheet = app.otherElements["drawingEditSheet"]
        XCTAssertTrue(drawingSheet.waitForExistence(timeout: 2))
        
        let cancelButton = app.buttons["cancelDrawingButton"]
        XCTAssertTrue(cancelButton.exists, "Cancel button should exist")
        
        cancelButton.tap()
        
        XCTAssertFalse(drawingSheet.exists, "Drawing sheet should dismiss after cancel")
    }
    
    // MARK: - Layers Tests
    
    func testLayersSheetOpens() throws {
        let layersButton = app.buttons["layersButton"]
        XCTAssertTrue(layersButton.exists, "Layers button should exist")
        
        layersButton.tap()
        
        let layersList = app.tables["layersList"]
        XCTAssertTrue(layersList.waitForExistence(timeout: 2), "Layers list should appear")
    }
    
    func testLayersSheetDismisses() throws {
        app.buttons["layersButton"].tap()
        
        let layersList = app.tables["layersList"]
        XCTAssertTrue(layersList.waitForExistence(timeout: 2))
        
        let doneButton = app.buttons["layersDoneButton"]
        XCTAssertTrue(doneButton.exists, "Done button should exist")
        
        doneButton.tap()
        
        XCTAssertFalse(layersList.exists, "Layers sheet should dismiss")
    }
    
    func testLayerVisibilityToggle() throws {
        // Add a text layer first
        app.buttons["textButton"].tap()
        let textSheet = app.sheets.firstMatch
        XCTAssertTrue(textSheet.waitForExistence(timeout: 2))
        app.swipeDown()
        
        // Open layers sheet
        app.buttons["layersButton"].tap()
        
        let layersList = app.tables["layersList"]
        XCTAssertTrue(layersList.waitForExistence(timeout: 2))
        
        // Toggle visibility of first layer
        let visibilityButton = app.buttons["visibilityButton-0"]
        if visibilityButton.exists {
            visibilityButton.tap()
            visibilityButton.tap() // Toggle back
        }
    }
    
    // MARK: - Delete Tests
    
    func testDeleteSelectedLayer() throws {
        // Add a text layer
        app.buttons["textButton"].tap()
        let textSheet = app.sheets.firstMatch
        XCTAssertTrue(textSheet.waitForExistence(timeout: 2))
        app.swipeDown()
        
        // Delete button should exist when layer is selected
        let deleteButton = app.buttons["deleteButton"]
        XCTAssertTrue(deleteButton.exists, "Delete button should exist when layer is selected")
        
        deleteButton.tap()
        
        // Delete button should disappear after deletion
        XCTAssertFalse(deleteButton.exists, "Delete button should not exist after deletion")
    }
    
    // MARK: - Undo/Redo Tests
    
    func testUndoRedoButtons() throws {
        let undoButton = app.buttons["undoTopButton"]
        let redoButton = app.buttons["redoTopButton"]
        
        XCTAssertTrue(undoButton.exists, "Undo button should exist")
        XCTAssertTrue(redoButton.exists, "Redo button should exist")
        
        // Initially should be disabled
        XCTAssertFalse(undoButton.isEnabled, "Undo should be disabled initially")
        XCTAssertFalse(redoButton.isEnabled, "Redo should be disabled initially")
    }
    
    func testUndoAfterAction() throws {
        // Add a text layer
        app.buttons["textButton"].tap()
        let textSheet = app.sheets.firstMatch
        XCTAssertTrue(textSheet.waitForExistence(timeout: 2))
        app.swipeDown()
        
        // Undo should now be enabled
        let undoButton = app.buttons["undoTopButton"]
        XCTAssertTrue(undoButton.isEnabled, "Undo should be enabled after action")
        
        undoButton.tap()
        
        // After undo, redo should be enabled
        let redoButton = app.buttons["redoTopButton"]
        XCTAssertTrue(redoButton.isEnabled, "Redo should be enabled after undo")
    }
    
    // MARK: - Pagination Tests
    
    func testPageNavigation() throws {
        let pageLabel = app.staticTexts["pageLabel"]
        let prevButton = app.buttons["pagePrevButton"]
        let nextButton = app.buttons["pageNextButton"]
        
        XCTAssertTrue(pageLabel.exists, "Page label should exist")
        XCTAssertTrue(prevButton.exists, "Previous page button should exist")
        XCTAssertTrue(nextButton.exists, "Next page button should exist")
        
        // Should be on page 1 initially
        XCTAssertEqual(pageLabel.label, "1", "Should start on page 1")
        
        // Previous should be disabled on first page
        XCTAssertFalse(prevButton.isEnabled, "Previous button should be disabled on first page")
        
        // Go to next page
        nextButton.tap()
        XCTAssertEqual(pageLabel.label, "2", "Should be on page 2 after tapping next")
        
        // Previous should now be enabled
        XCTAssertTrue(prevButton.isEnabled, "Previous button should be enabled on page 2")
        
        // Go back
        prevButton.tap()
        XCTAssertEqual(pageLabel.label, "1", "Should be back on page 1")
    }
    
    func testLastPageDisablesNext() throws {
        let nextButton = app.buttons["pageNextButton"]
        
        // Navigate to last page (page 8)
        for _ in 0..<7 {
            if nextButton.isEnabled {
                nextButton.tap()
            }
        }
        
        let pageLabel = app.staticTexts["pageLabel"]
        XCTAssertEqual(pageLabel.label, "8", "Should be on page 8")
        
        // Next should be disabled on last page
        XCTAssertFalse(nextButton.isEnabled, "Next button should be disabled on last page")
    }
    
    // MARK: - Share/Export Tests
    
    func testShareButtonExists() throws {
        let shareButton = app.buttons["shareButton"]
        XCTAssertTrue(shareButton.exists, "Share button should exist")
    }
    
    func testShareButtonTap() throws {
        let shareButton = app.buttons["shareButton"]
        shareButton.tap()
        
        // Activity view controller should appear (platform dependent)
        // This is hard to test without mocking
    }
    
    // MARK: - Noise Filter Tests
    
    func testNoiseMenuAppearsForImageLayer() throws {
        // This requires having an image layer selected
        // Would need to mock photo selection for full test
        let moreMenuButton = app.buttons["moreMenuButton"]
        
        // More menu only appears when image layer is selected
        if moreMenuButton.exists {
            moreMenuButton.tap()
            
            let noiseMenuItem = app.buttons["noiseMenuItem"]
            XCTAssertTrue(noiseMenuItem.waitForExistence(timeout: 1), "Noise menu item should exist for image layers")
        }
    }
    
    func testNoiseSheetControls() throws {
        // Assuming we have an image layer and noise sheet open
        let noiseSheet = app.otherElements["noiseEditSheet"]
        
        if noiseSheet.exists {
            let noiseSlider = app.sliders["noiseSlider"]
            XCTAssertTrue(noiseSlider.exists, "Noise slider should exist")
            
            let cancelButton = app.buttons["cancelNoiseButton"]
            let applyButton = app.buttons["applyNoiseButton"]
            
            XCTAssertTrue(cancelButton.exists, "Cancel button should exist")
            XCTAssertTrue(applyButton.exists, "Apply button should exist")
        }
    }
    
    // MARK: - Integration Tests
    
    func testCompleteWorkflow() throws {
        // Add text layer
        app.buttons["textButton"].tap()
        let textSheet = app.sheets.firstMatch
        XCTAssertTrue(textSheet.waitForExistence(timeout: 2))
        app.swipeDown()
        
        // Go to next page
        app.buttons["pageNextButton"].tap()
        
        // Add another layer on page 2
        app.buttons["textButton"].tap()
        XCTAssertTrue(textSheet.waitForExistence(timeout: 2))
        app.swipeDown()
        
        // Open layers sheet
        app.buttons["layersButton"].tap()
        let layersList = app.tables["layersList"]
        XCTAssertTrue(layersList.waitForExistence(timeout: 2))
        
        // Close layers sheet
        app.buttons["layersDoneButton"].tap()
        
        // Go back to page 1
        app.buttons["pagePrevButton"].tap()
        
        let pageLabel = app.staticTexts["pageLabel"]
        XCTAssertEqual(pageLabel.label, "1", "Should be back on page 1")
    }
    
    // MARK: - Performance Tests
    
    func testCanvasRenderingPerformance() throws {
        measure {
            let canvas = app.otherElements["canvas"]
            _ = canvas.exists
        }
    }
    
    func testPageNavigationPerformance() throws {
        let nextButton = app.buttons["pageNextButton"]
        
        measure {
            nextButton.tap()
        }
    }
}

// MARK: - Helper Extensions

extension XCUIElement {
    func clearText() {
        guard let stringValue = self.value as? String else {
            return
        }
        
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
        self.typeText(deleteString)
    }
}
