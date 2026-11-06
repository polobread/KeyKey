import Foundation
import Testing
@testable import KeyKeyEngine

@Suite("Keyboard layout profiles")
struct KeyboardLayoutProfileTests {
    @Test func registeredProfilesKeepEveryPlacementInsideTheAvailableWidth() {
        #expect(Set(KeyboardLayoutProfile.available.map(\.id)).count == KeyboardLayoutProfile.available.count)
        for profile in KeyboardLayoutProfile.available {
            #expect(!profile.id.isEmpty)
            for orientation in KeyboardLayoutProfile.Orientation.allCases {
                for plane in KeyboardLayoutProfile.Plane.allCases {
                    for shifted in [false, true] {
                        for position in KeyboardDeleteShiftPosition.allCases {
                            let rows = profile.resolvedRows(orientation: orientation, plane: plane,
                                                            shifted: shifted, deleteShiftPosition: position)
                            #expect(!rows.isEmpty)
                            for (index, row) in rows.enumerated() {
                                #expect(!row.isEmpty)
                                for width in [314.0, 446, 649, 820] {
                                    let geometry = profile.keyRowGeometry(for: rows, plane: plane, rowIndex: index)
                                    #expect(geometry.weights.allSatisfy { $0 > 0 && $0.isFinite })
                                    let frames = geometry.frames(width: width, height: 44, spacing: profile.keySpacing)
                                    expectUsableFrames(frames, width: width, expectedCount: geometry.weights.count,
                                                       splitIndex: geometry.splitIndex, fillsWidth: false)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func registeredProfilesKeepFunctionAndCompositionControlsUsable() {
        for profile in KeyboardLayoutProfile.available {
            #expect(profile.compositionCellCount > 0)
            for width in [314.0, 446, 649, 820] {
                let split = profile.splitGeometry
                let compositionWeights = Array(repeating: 1.0,
                    count: profile.compositionCellCount + (split != nil ? 1 : 0))
                let composition = KeyboardRowGeometry.frames(width: width, height: 44,
                    weights: compositionWeights, splitIndex: split?.compositionSplit,
                    spacing: profile.stripSpacing)
                expectUsableFrames(composition, width: width, expectedCount: compositionWeights.count,
                                   splitIndex: split?.compositionSplit)
                for position in KeyboardDeleteShiftPosition.allCases {
                    for globe in [false, true] {
                        var keys = profile.functionKeys(deleteShiftPosition: position)
                        if split != nil, let space = keys.firstIndex(of: "SPACE") {
                            keys.insert("SPACE", at: space + 1)
                        }
                        if globe { keys.insert(KeyboardLayout.inputModeSwitchKey, at: 0) }
                        #expect(!keys.isEmpty)
                        let weights = keys.map { profile.functionWeight(for: $0) }
                        #expect(weights.allSatisfy { $0 > 0 && $0.isFinite })
                        let splitIndex = split == nil ? nil : keys.firstIndex(of: "SPACE").map { $0 + 1 }
                        let controls = KeyboardRowGeometry.frames(width: width, height: 44,
                            weights: weights, splitIndex: splitIndex, spacing: profile.keySpacing)
                        expectUsableFrames(controls, width: width, expectedCount: keys.count,
                                           splitIndex: splitIndex)
                        guard controls.count == weights.count else { continue }
                        let groups = splitIndex.map { [0..<$0, $0..<weights.count] } ?? [0..<weights.count]
                        for group in groups {
                            guard let first = group.first else { continue }
                            for index in group {
                                #expect(abs(controls[index].width / controls[first].width
                                    - weights[index] / weights[first]) < 0.001)
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func registeredProfilesKeepInputKeysAndOneOfEachControlWhenDeleteAndShiftSwap() {
        let actions: Set<String> = ["MODE", "SYMBOL", "SETTINGS", "SPACE", "BACKSPACE", "ENTER", "SHIFT", "EMOJI"]
        for profile in KeyboardLayoutProfile.available {
            for orientation in KeyboardLayoutProfile.Orientation.allCases {
                for plane in KeyboardLayoutProfile.Plane.allCases {
                    for shifted in [false, true] {
                        let baseline = KeyboardLayoutProfile.aligned.rows(orientation: orientation, plane: plane, shifted: shifted)
                            .flatMap { $0 }
                            .filter { !(profile.id == "standard" && (plane == .cangjie || plane == .simplex) && $0 == "/") }
                        for position in KeyboardDeleteShiftPosition.allCases {
                            let rows = profile.resolvedRows(orientation: orientation, plane: plane,
                                                            shifted: shifted, deleteShiftPosition: position)
                            var functions = profile.functionKeys(deleteShiftPosition: position)
                            if profile.splitGeometry != nil, let space = functions.firstIndex(of: "SPACE") {
                                functions.insert("SPACE", at: space + 1)
                            }
                            let rowKeys = rows.flatMap { $0 }
                            #expect(rowKeys.filter { !actions.contains($0) }.sorted()
                                == baseline.filter { !actions.contains($0) }.sorted())
                            let keys = rowKeys + functions
                            for action in actions {
                                let expected = action == "SPACE" && profile.splitGeometry != nil ? 2
                                    : action == "EMOJI" ? baseline.filter { $0 == action }.count : 1
                                #expect(keys.filter { $0 == action }.count == expected)
                            }
                            if let enterIndex = functions.firstIndex(of: "ENTER"), enterIndex > 0 {
                                #expect(functions[enterIndex - 1] == (position == .aboveEnter ? "SHIFT" : "BACKSPACE"))
                            } else {
                                Issue.record("The function row needs a Delete/Shift control before Enter")
                            }
                            let expectedRowAction = position == .aboveEnter ? "BACKSPACE" : "SHIFT"
                            #expect(rowKeys.filter { $0 == expectedRowAction }.count == 1)
                            #expect(profile.functionWeight(for: "SHIFT") == profile.functionWeight(for: "BACKSPACE"))
                        }
                    }
                }
            }
        }
    }

    @Test func profileChangesKeepTheSameMetricsForEveryDeviceShape() {
        for profile in KeyboardLayoutProfile.available {
            for compactHeight in [false, true] {
                for isPad in [false, true] {
                    for regularWidth in [false, true] {
                        #expect(profile.metrics(compactHeight: compactHeight, isPad: isPad, regularWidth: regularWidth)
                            == KeyboardLayoutProfile.aligned.metrics(compactHeight: compactHeight,
                                                                  isPad: isPad, regularWidth: regularWidth))
                    }
                }
            }
        }
    }

    @Test func staggeredGeometryUsesTheDeclaredRowsInsteadOfAFixedColumnCount() {
        let rows = [["a", "b", "c"], ["d", "e", "SHIFT"], ["f", "g"], ["h", "i", "BACKSPACE"]]
        for profile in KeyboardLayoutProfile.available where profile.usesStaggeredRows {
            let first = profile.keyRowGeometry(for: rows, plane: .bopomofo, rowIndex: 0)
            let second = profile.keyRowGeometry(for: rows, plane: .bopomofo, rowIndex: 1)
            let last = profile.keyRowGeometry(for: rows, plane: .bopomofo, rowIndex: rows.count - 1)
            #expect(abs(first.totalUnits - (3 + 1.0 / 3)) < 0.001)
            #expect(first.leadingUnits == 0 && last.leadingUnits == 0)
            for width in [314.0, 649] {
                let firstFrames = first.frames(width: width, height: 44, spacing: profile.keySpacing)
                let secondFrames = second.frames(width: width, height: 44, spacing: profile.keySpacing)
                let lastFrames = last.frames(width: width, height: 44, spacing: profile.keySpacing)
                #expect(firstFrames.first?.minX == 0)
                #expect(secondFrames.first!.minX > firstFrames.first!.minX)
                #expect(lastFrames.first?.minX == 0)
                #expect(abs(secondFrames.last!.maxX - width) < 0.001)
                #expect(abs(lastFrames.last!.maxX - width) < 0.001)
                #expect(lastFrames.last!.width > lastFrames.first!.width)
            }
        }
    }

    @Test func staggeredRowsShiftOnlyTheMiddleRowsAndKeepTheirControlsReachable() {
        for profile in KeyboardLayoutProfile.available where profile.usesStaggeredRows {
            for orientation in KeyboardLayoutProfile.Orientation.allCases {
                for plane in KeyboardLayoutProfile.Plane.allCases {
                    for shifted in [false, true] {
                        for position in KeyboardDeleteShiftPosition.allCases {
                            let rows = profile.resolvedRows(orientation: orientation, plane: plane,
                                                            shifted: shifted, deleteShiftPosition: position)
                            let offsets = profile.rowOffsets(for: plane)
                            #expect(rows.count == offsets.count)
                            guard rows.count == offsets.count else { continue }
                            let total = zip(rows, offsets).map { Double($0.0.count) + $0.1 }.max()!
                            for index in rows.indices {
                                let geometry = profile.keyRowGeometry(for: rows, plane: plane, rowIndex: index)
                                #expect(abs(geometry.leadingUnits - offsets[index]) < 0.001)
                                #expect(abs(geometry.totalUnits - total) < 0.001)
                                #expect(geometry.splitIndex == nil)
                                #expect(geometry.weights.count == rows[index].count)
                                if rows[index].last == "SHIFT" || rows[index].last == "BACKSPACE" {
                                    #expect(abs(geometry.weights.reduce(0, +) + geometry.leadingUnits - total) < 0.001)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func staggeredPlanesUseOnePitchAcrossAllReadingRows() throws {
        for profile in KeyboardLayoutProfile.available where profile.usesStaggeredRows {
            for orientation in KeyboardLayoutProfile.Orientation.allCases {
                for plane in KeyboardLayoutProfile.Plane.allCases {
                    for shifted in [false, true] {
                        for position in KeyboardDeleteShiftPosition.allCases {
                            let rows = profile.resolvedRows(orientation: orientation, plane: plane,
                                shifted: shifted, deleteShiftPosition: position)
                            let geometries = rows.indices.map { profile.keyRowGeometry(for: rows, plane: plane, rowIndex: $0) }
                            for width in [314.0, 446, 649, 820] {
                                let frames = geometries.map {
                                    $0.frames(width: width, height: 44, spacing: profile.keySpacing)
                                }
                                let first = try #require(frames.first?.first)
                                let pitch = first.width + profile.keySpacing
                                var middleStarts: [Double] = []
                                for (geometry, rowFrames) in zip(geometries, frames) {
                                    let start = try #require(rowFrames.first)
                                    #expect(abs(start.minX - geometry.leadingUnits * pitch) < 0.000001)
                                    for (weight, frame) in zip(geometry.weights, rowFrames) where abs(weight - 1) < 0.000001 {
                                        #expect(abs(frame.width - first.width) < 0.000001)
                                    }
                                    if geometry.leadingUnits == 0 {
                                        // In particular, ㄈ returns to exactly the ㄅ centre.
                                        #expect(abs(start.midX - first.midX) < 0.000001)
                                    } else {
                                        middleStarts.append(start.minX)
                                    }
                                }
                                for (index, start) in middleStarts.sorted().enumerated() {
                                    #expect(abs(start - Double(index + 1) * pitch / 3) < 0.000001)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func standardTableBottomRowMovesOnePitchWithoutMovingTheRightControl() throws {
        let profile = KeyboardLayoutProfile.standard
        var previous = profile
        previous.planeGeometryOverrides = [:]
        let expectedOffsets: [Double] = [0, 1.0 / 3.0, 2.0 / 3.0, 1]
        for orientation in KeyboardLayoutProfile.Orientation.allCases {
            for plane in [KeyboardLayoutProfile.Plane.cangjie, .simplex] {
                #expect(profile.rowOffsets(for: plane) == expectedOffsets)
                for shifted in [false, true] {
                    for position in KeyboardDeleteShiftPosition.allCases {
                        let oldRows = KeyboardLayoutProfile.aligned.resolvedRows(orientation: orientation,
                            plane: plane, shifted: shifted, deleteShiftPosition: position)
                        let rows = profile.resolvedRows(orientation: orientation, plane: plane,
                            shifted: shifted, deleteShiftPosition: position)
                        let last = try #require(rows.indices.last)
                        #expect(rows[last].first == "z")
                        #expect(!rows[last].contains("/"))
                        #expect(rows[last] == oldRows[last].filter { $0 != "/" })
                        #expect(Array(rows.dropLast()) == Array(oldRows.dropLast()))
                        let x = try #require(oldRows[last].firstIndex(of: "x"))
                        for width in [314.0, 446, 649, 820] {
                            let old = previous.keyRowGeometry(for: oldRows, plane: plane, rowIndex: last)
                                .frames(width: width, height: 44, spacing: profile.keySpacing)
                            let frames = profile.keyRowGeometry(for: rows, plane: plane, rowIndex: last)
                                .frames(width: width, height: 44, spacing: profile.keySpacing)
                            let first = try #require(frames.first)
                            #expect(first == old[x], "重(z) takes the old 難(x) hit target")
                            #expect(frames.last == old.last, "Delete/Shift keeps the old rightmost target")
                            let leadingGap = CGPoint(x: first.minX / 2, y: first.midY)
                            #expect(first.minX > 0)
                            #expect(!frames.contains { $0.contains(leadingGap) }, "No fake character key fills the leading gap")
                            for row in rows.indices.dropLast() {
                                #expect(profile.keyRowGeometry(for: rows, plane: plane, rowIndex: row)
                                    .frames(width: width, height: 44, spacing: profile.keySpacing)
                                    == previous.keyRowGeometry(for: oldRows, plane: plane, rowIndex: row)
                                    .frames(width: width, height: 44, spacing: profile.keySpacing))
                            }
                            for area in KeyboardKeycapArea.allCases {
                                let cap = area.frame(in: first.insetBy(dx: 1, dy: 1))
                                #expect(abs(cap.midX - old[x].midX) < 0.000001)
                                #expect(abs(cap.midY - old[x].midY) < 0.000001)
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func tableRowOverrideLeavesOtherLayoutsAndPlanesUnchanged() {
        let expectedOffsets: [Double] = [0, 1.0 / 3.0, 2.0 / 3.0, 0]
        for profile in KeyboardLayoutProfile.available {
            for orientation in KeyboardLayoutProfile.Orientation.allCases {
                for plane in KeyboardLayoutProfile.Plane.allCases {
                    if profile.id == "standard" && (plane == .cangjie || plane == .simplex) { continue }
                    #expect(profile.planeGeometryOverrides[plane] == nil)
                    for shifted in [false, true] {
                        #expect(profile.rows(orientation: orientation, plane: plane, shifted: shifted)
                            == KeyboardLayoutProfile.aligned.rows(orientation: orientation, plane: plane, shifted: shifted))
                        if profile.usesStaggeredRows {
                            #expect(profile.rowOffsets(for: plane) == expectedOffsets)
                        }
                    }
                }
            }
        }
    }

    @Test func placementSelectionKeepsDirectionsAndInputPlanesIndependent() {
        func placements(_ direction: String) -> KeyboardLayoutProfile.Placements {
            func placement(_ plane: KeyboardLayoutProfile.Plane) -> KeyboardLayoutProfile.Placement {
                let label = "\(direction).\(plane)"
                return .init(rows: [[label]], shiftedRows: [[label + ".shifted"]])
            }
            return .init(bopomofo: placement(.bopomofo), cangjie: placement(.cangjie),
                         simplex: placement(.simplex), english: placement(.english),
                         numberSymbols: placement(.numberSymbols))
        }
        let baseline = KeyboardLayoutProfile.aligned
        let profile = KeyboardLayoutProfile(id: "routing-fixture", displayName: "Routing fixture",
            portrait: placements("portrait"), landscape: placements("landscape"),
            functionKeys: baseline.functionKeys, functionWeights: baseline.functionWeights,
            keySpacing: baseline.keySpacing, stripSpacing: baseline.stripSpacing,
            compositionCellCount: baseline.compositionCellCount, splitGeometry: nil,
            portraitMetrics: baseline.portraitMetrics, compactMetrics: baseline.compactMetrics,
            wideMetrics: baseline.wideMetrics)
        // These independent labels catch accidentally reusing another orientation or plane.
        let inputs: [(ChineseInputMethod, KeyboardInput.InputMode, KeyboardLayoutProfile.Plane)] = [
            (.smart, .bopomofo, .bopomofo), (.traditional, .bopomofo, .bopomofo),
            (.cangjie, .bopomofo, .cangjie), (.simplex, .bopomofo, .simplex)
        ] + ChineseInputMethod.allCases.flatMap { method in [
            (method, KeyboardInput.InputMode.english, KeyboardLayoutProfile.Plane.english),
            (method, KeyboardInput.InputMode.number, KeyboardLayoutProfile.Plane.numberSymbols)
        ] }
        for orientation in KeyboardLayoutProfile.Orientation.allCases {
            for (method, mode, expectedPlane) in inputs {
                for shifted in [false, true] {
                    let label = "\(orientation).\(expectedPlane)" + (shifted ? ".shifted" : "")
                    #expect(profile.rows(orientation: orientation, inputMethod: method,
                                         mode: mode, shifted: shifted) == [[label]])
                }
            }
        }
    }

    @Test func layoutRegistryContainsIndependentLayoutsWithoutOldStylePresets() {
        let ids = Set(KeyboardLayoutProfile.available.map(\.id))
        #expect(ids.count == KeyboardLayoutProfile.available.count)
        #expect(Set(["standard", "aligned", "aligned-split"]).isSubset(of: ids))
        #expect(ids.isDisjoint(with: ["full", "split", "staggered", "full-spaced", "large-full", "large-staggered"]))
        #expect(KeyboardLayoutProfile.standard.usesStaggeredRows)
        #expect(!KeyboardLayoutProfile.aligned.usesStaggeredRows)
        #expect(KeyboardLayoutProfile.alignedSplit.splitGeometry != nil)
    }

    @Test func independentChoicesPersistWithoutReorderingOrResizingKeys() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let settings = KeyboardLayoutProfileSettings(defaults: defaults)
        for profile in KeyboardLayoutProfile.available {
            for area in KeyboardKeycapArea.allCases {
                for font in KeyboardKeyFontSize.allCases {
                    for position in KeyboardDeleteShiftPosition.allCases {
                        settings.setProfile(profile)
                        settings.setKeycapArea(area)
                        settings.setFontSize(font)
                        settings.setDeleteShiftPosition(position)
                        let restored = KeyboardLayoutProfileSettings(defaults: defaults)
                        #expect(restored.profile == profile)
                        #expect(restored.keycapArea == area)
                        #expect(restored.fontSize == font)
                        #expect(restored.deleteShiftPosition == position)
                        for orientation in KeyboardLayoutProfile.Orientation.allCases {
                            for plane in KeyboardLayoutProfile.Plane.allCases {
                                for shifted in [false, true] {
                                    let expectedRows = profile.resolvedRows(orientation: orientation, plane: plane,
                                        shifted: shifted, deleteShiftPosition: position)
                                    let rows = restored.profile.resolvedRows(orientation: orientation, plane: plane,
                                        shifted: shifted, deleteShiftPosition: restored.deleteShiftPosition)
                                    #expect(rows == expectedRows)
                                    for width in [314.0, 649, 820] {
                                        for index in rows.indices {
                                            let expected = profile.keyRowGeometry(for: expectedRows, plane: plane, rowIndex: index)
                                                .frames(width: width, height: 44, spacing: profile.keySpacing)
                                            let frames = restored.profile.keyRowGeometry(for: rows, plane: plane, rowIndex: index)
                                                .frames(width: width, height: 44, spacing: restored.profile.keySpacing)
                                            // Spacing and font size never change action order or hit targets.
                                            #expect(frames == expected)
                                            for hit in frames {
                                                let inset = profile.usesStaggeredRows ? 1.0 : 0
                                                let originalCap = hit.insetBy(dx: inset, dy: inset)
                                                let cap = restored.keycapArea.frame(in: originalCap)
                                                #expect(abs(cap.midX - hit.midX) < 0.000001)
                                                #expect(abs(cap.midY - hit.midY) < 0.000001)
                                                #expect(abs(cap.width * cap.height / (originalCap.width * originalCap.height)
                                                    - area.areaRatio) < 0.000001)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func freshAndUnknownPreferencesUseTheNewDefaults() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let settings = KeyboardLayoutProfileSettings(defaults: defaults)
        #expect(settings.profile == .standard)
        #expect(settings.keycapArea == .small)
        #expect(settings.fontSize == .normal)
        #expect(settings.deleteShiftPosition == .aboveEnter)
        for key in ["keyboardLayoutVariant", "keyboardKeycapSpacing", "keyboardKeyFontLevel", "keyboardDeleteShiftPosition"] {
            defaults.set("unknown", forKey: key)
        }
        #expect(settings.profile == .standard)
        #expect(settings.keycapArea == .small)
        #expect(settings.fontSize == .normal)
        #expect(settings.deleteShiftPosition == .aboveEnter)
    }

    @Test func legacyPresetsResolveWithoutRewritingOrApplyingInactiveSpacing() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let settings = KeyboardLayoutProfileSettings(defaults: defaults)
        let cases: [(String, KeyboardLayoutProfile, KeyboardKeyFontSize)] = [
            ("full", .aligned, .normal), ("staggered", .standard, .normal),
            ("large-full", .aligned, .extraLarge), ("large-staggered", .standard, .extraLarge),
            ("split", .alignedSplit, .normal), ("full-spaced", .aligned, .normal)
        ]
        for key in ["keyboardLayoutProfile", "keyboardPresentation"] {
            for (oldID, profile, font) in cases {
                defaults.removeObject(forKey: "keyboardLayoutProfile")
                defaults.removeObject(forKey: "keyboardPresentation")
                defaults.set(oldID, forKey: key)
                for oldArea in ["90", "85"] {
                    defaults.set(oldArea, forKey: "keyboardKeycapArea")
                    defaults.set("left-of-enter", forKey: "keyboardDeleteShiftPosition")
                    #expect(settings.profile == profile)
                    #expect(settings.fontSize == font)
                    #expect(settings.deleteShiftPosition == .leftOfEnter)
                    let area: KeyboardKeycapArea = oldID == "full-spaced"
                        ? (oldArea == "85" ? .large : .medium) : .small
                    #expect(settings.keycapArea == area)
                    #expect(defaults.string(forKey: key) == oldID)
                    #expect(defaults.string(forKey: "keyboardKeycapArea") == oldArea)
                    #expect(defaults.object(forKey: "keyboardLayoutVariant") == nil)
                    #expect(defaults.object(forKey: "keyboardKeycapSpacing") == nil)
                    #expect(defaults.object(forKey: "keyboardKeyFontSize") == nil)
                }
            }
        }
        defaults.set("unknown", forKey: "keyboardLayoutProfile")
        defaults.set("split", forKey: "keyboardPresentation")
        #expect(settings.profile == .alignedSplit)
    }

    @Test func changingOneNewChoicePreservesOtherLegacyDerivedChoices() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let settings = KeyboardLayoutProfileSettings(defaults: defaults)
        defaults.set("large-full", forKey: "keyboardLayoutProfile")
        defaults.set("left-of-enter", forKey: "keyboardDeleteShiftPosition")
        settings.setProfile(.standard)
        #expect(settings.profile == .standard)
        #expect(settings.fontSize == .extraLarge)
        #expect(settings.keycapArea == .small)
        #expect(settings.deleteShiftPosition == .leftOfEnter)
        #expect(defaults.string(forKey: "keyboardLayoutProfile") == "large-full")

        defaults.set("full-spaced", forKey: "keyboardLayoutProfile")
        defaults.set("85", forKey: "keyboardKeycapArea")
        #expect(settings.keycapArea == .large)
        settings.setProfile(.standard)
        #expect(settings.keycapArea == .large)
        #expect(settings.fontSize == .normal)
        settings.setFontSize(.large)
        #expect(settings.profile == .standard)
        #expect(settings.keycapArea == .large)
        settings.setKeycapArea(.small)
        #expect(settings.fontSize == .large)
        #expect(settings.deleteShiftPosition == .leftOfEnter)
        settings.setDeleteShiftPosition(.aboveEnter)
        #expect(settings.fontSize == .large)
        #expect(settings.keycapArea == .small)
        #expect(defaults.string(forKey: "keyboardLayoutProfile") == "full-spaced")
        #expect(defaults.string(forKey: "keyboardKeycapArea") == "85")
    }

    @Test func appGroupRevisionsKeepAllFourChoicesIndependent() {
        let localName = "KeyboardLayoutProfileTests.local.\(UUID())"
        let sharedName = "KeyboardLayoutProfileTests.shared.\(UUID())"
        let local = UserDefaults(suiteName: localName)!
        let shared = UserDefaults(suiteName: sharedName)!
        defer {
            local.removePersistentDomain(forName: localName)
            shared.removePersistentDomain(forName: sharedName)
        }
        let keyboard = KeyboardLayoutProfileSettings(defaults: local, sharedDefaults: shared)
        let app = KeyboardLayoutProfileSettings(defaults: local, sharedDefaults: shared, writesShared: true)
        app.setProfile(.aligned)
        app.setKeycapArea(.large)
        app.setFontSize(.large)
        app.setDeleteShiftPosition(.leftOfEnter)
        #expect(keyboard.profile == .aligned)
        #expect(keyboard.keycapArea == .large)
        #expect(keyboard.fontSize == .large)
        #expect(keyboard.deleteShiftPosition == .leftOfEnter)
        keyboard.setProfile(.alignedSplit)
        keyboard.setKeycapArea(.medium)
        keyboard.setFontSize(.normal)
        keyboard.setDeleteShiftPosition(.aboveEnter)
        #expect(app.profile == .aligned)
        #expect(app.keycapArea == .large)
        #expect(app.fontSize == .large)
        #expect(app.deleteShiftPosition == .leftOfEnter)
        app.setProfile(.standard)
        #expect(keyboard.profile == .standard)
        #expect(keyboard.keycapArea == .medium)
        #expect(keyboard.fontSize == .normal)
        #expect(keyboard.deleteShiftPosition == .aboveEnter)
        app.setFontSize(.large)
        #expect(keyboard.fontSize == .large)
        #expect(keyboard.keycapArea == .medium)
        app.setKeycapArea(.small)
        #expect(keyboard.keycapArea == .small)
        #expect(keyboard.deleteShiftPosition == .aboveEnter)
        app.setDeleteShiftPosition(.leftOfEnter)
        let restored = KeyboardLayoutProfileSettings(defaults: local, sharedDefaults: shared)
        #expect(restored.profile == .standard)
        #expect(restored.keycapArea == .small)
        #expect(restored.fontSize == .large)
        #expect(restored.deleteShiftPosition == .leftOfEnter)
    }

    @Test func fourFontLevelsPreserveLargeIdentifiersAndUseOnlyNormalHints() {
        #expect(KeyboardKeyFontSize.allCases.map(\.rawValue) == ["normal", "medium", "large", "extra-large"])
        #expect(KeyboardKeyFontSize.allCases.map(\.displayName) == ["標準", "中", "大", "特大"])
        #expect(KeyboardKeyFontSize(rawValue: "large") == .large)
        #expect(KeyboardKeyFontSize.allCases.filter(\.showsKeyHints) == [.normal])
    }

    @Test func keyFontLevelsUseAvailableEndpointsAndEqualRatios() {
        for (normal, full) in [(18.0, 30.0), (11, 20), (32.4, 28)] {
            let levels = KeyboardKeyFontSize.allCases.map {
                $0.keyPointSize(normal: normal, largeFit: full)
            }
            #expect(levels[0] == min(normal, full))
            #expect(levels[3] == full)
            let ratios = zip(levels.dropFirst(), levels).map { $0 / $1 }
            #expect(ratios.allSatisfy { abs($0 - ratios[0]) < 0.000001 })
            for (level, expected) in zip(KeyboardKeyFontSize.allCases, levels) {
                #expect(abs(level.keyPointSize(normal: normal * 2, largeFit: full * 2)
                    - expected * 2) < 0.000001)
            }
        }
    }

    @Test func stripFontLevelsHaveIndependentPrimaryTextTargets() {
        for base in [11.0, 12, 14, 18] {
            for (level, scale) in zip(KeyboardKeyFontSize.allCases, [1.0, 1.15, 1.30, 1.45]) {
                #expect(abs(level.stripPointSize(base: base) - base * scale) < 0.000001)
            }
        }
    }

    @Test func oldSavedLargeBecomesExtraLargeWhileNewLargeUsesItsOwnKey() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let settings = KeyboardLayoutProfileSettings(defaults: defaults)
        defaults.set("large", forKey: "keyboardKeyFontSize")
        #expect(settings.fontSize == .extraLarge)
        #expect(defaults.object(forKey: "keyboardKeyFontLevel") == nil)
        settings.setFontSize(.large)
        #expect(settings.fontSize == .large)
        #expect(defaults.string(forKey: "keyboardKeyFontLevel") == "large")
        #expect(defaults.string(forKey: "keyboardKeyFontSize") == "large")
        defaults.removeObject(forKey: "keyboardKeyFontLevel")
        defaults.set("normal", forKey: "keyboardKeyFontSize")
        #expect(settings.fontSize == .normal)
        #expect(defaults.object(forKey: "keyboardKeyFontLevel") == nil)
    }

    @Test func keycapIntervalsUseOriginalNinetyAndEightyPercentArea() {
        for bounds in [CGRect(x: 0, y: 0, width: 28, height: 44), CGRect(x: 37, y: 11, width: 72, height: 35)] {
            for (area, ratio) in [(KeyboardKeycapArea.small, 1.0), (.medium, 0.9), (.large, 0.8)] {
                let cap = area.frame(in: bounds)
                #expect(abs(area.areaRatio - ratio) < 0.000001)
                #expect(abs(area.linearScale * area.linearScale - ratio) < 0.000001)
                #expect(abs(cap.width * cap.height / (bounds.width * bounds.height) - ratio) < 0.000001)
                #expect(abs(cap.midX - bounds.midX) < 0.000001)
                #expect(abs(cap.midY - bounds.midY) < 0.000001)
            }
            #expect(KeyboardKeycapArea.small.frame(in: bounds) == bounds)
        }
    }

    private let defaultsSuiteName = "KeyboardLayoutProfileTests.\(UUID())"
    private func makeDefaults() -> UserDefaults { UserDefaults(suiteName: defaultsSuiteName)! }

    private func expectUsableFrames(_ frames: [CGRect], width: Double,
                                    expectedCount: Int, splitIndex: Int?, fillsWidth: Bool = true) {
        #expect(frames.count == expectedCount)
        #expect(frames.allSatisfy {
            $0.width > 0 && $0.width.isFinite && $0.minX >= 0 && $0.maxX <= width + 0.001
        })
        for index in frames.indices.dropFirst() { #expect(frames[index - 1].maxX <= frames[index].minX + 0.001) }
        if let splitIndex {
            #expect(splitIndex > 0 && splitIndex < frames.count)
            guard splitIndex > 0 && splitIndex < frames.count else { return }
            #expect(frames[splitIndex - 1].maxX < width / 2)
            #expect(frames[splitIndex].minX > width / 2)
            #expect(abs(frames[splitIndex - 1].maxX + frames[splitIndex].minX - width) < 0.001)
        } else if fillsWidth, let last = frames.last {
            #expect(abs(last.maxX - width) < 0.001)
        }
    }
}

/// Exact dimensions belong to this existing preset, not every registered profile.
@Suite("Existing split profile")
struct SplitKeyboardLayoutProfileTests {
    private let widths = [240.0, 314, 446, 599, 600, 820]

    @Test func splitPresetKeepsSixKeysPerSideAcrossEveryPlacementAndWidth() throws {
        let profile = KeyboardLayoutProfile.alignedSplit
        let split = try #require(profile.splitGeometry)
        #expect(split.punctuation == ["，", "。", "、", "？"])
        for orientation in KeyboardLayoutProfile.Orientation.allCases {
            for plane in KeyboardLayoutProfile.Plane.allCases {
                for shifted in [false, true] {
                    for position in KeyboardDeleteShiftPosition.allCases {
                        let rows = profile.resolvedRows(orientation: orientation, plane: plane,
                            shifted: shifted, deleteShiftPosition: position)
                        #expect(rows.count == split.punctuation.count)
                        for index in rows.indices {
                            let geometry = profile.keyRowGeometry(for: rows, plane: plane, rowIndex: index)
                            #expect(geometry.weights.count == rows[index].count + 1)
                            #expect(geometry.splitIndex == split.keySplit)
                            for width in widths {
                                let frames = geometry.frames(width: width, height: 44, spacing: profile.keySpacing)
                                expectBalancedSlots(frames, splitIndex: split.keySplit, width: width, height: 44)
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func splitPresetKeepsCompositionAndCandidateControlsBalancedAtEveryWidth() throws {
        let profile = KeyboardLayoutProfile.alignedSplit
        let split = try #require(profile.splitGeometry)
        // The dismiss slot is a control, not a twelfth editable syllable.
        #expect(profile.compositionCellCount == 11)
        for width in widths {
            let composition = KeyboardRowGeometry.frames(width: width, height: 44,
                weights: Array(repeating: 1, count: profile.compositionCellCount + 1),
                splitIndex: split.compositionSplit, spacing: profile.stripSpacing)
            expectBalancedSlots(composition, splitIndex: split.compositionSplit, width: width, height: 44)
            let candidates = KeyboardRowGeometry.frames(width: width, height: 44,
                weights: Array(repeating: 1, count: KeyboardInput.candidatesPerPage + 3),
                splitIndex: split.candidateSplit, spacing: profile.stripSpacing)
            expectBalancedSlots(candidates, splitIndex: split.candidateSplit, width: width, height: 44)
        }
    }

    @Test func splitPresetPreservesItsFunctionKeyProportionsAtEveryWidth() throws {
        let profile = KeyboardLayoutProfile.alignedSplit
        let split = try #require(profile.splitGeometry)
        for width in widths {
            for position in KeyboardDeleteShiftPosition.allCases {
                for globe in [false, true] {
                    var keys = profile.functionKeys(deleteShiftPosition: position)
                    let space = try #require(keys.firstIndex(of: "SPACE"))
                    keys.insert("SPACE", at: space + 1)
                    if globe { keys.insert(KeyboardLayout.inputModeSwitchKey, at: 0) }
                    #expect(keys.allSatisfy { !split.punctuation.contains($0) })
                    let boundary = try #require(keys.firstIndex(of: "SPACE")) + 1
                    let controls = KeyboardRowGeometry.frames(width: width, height: 44,
                        weights: keys.map { profile.functionWeight(for: $0) },
                        splitIndex: boundary, spacing: profile.keySpacing)
                    let mode = try #require(keys.firstIndex(of: "MODE"))
                    let symbols = try #require(keys.firstIndex(of: "SYMBOL"))
                    let settings = try #require(keys.firstIndex(of: "SETTINGS"))
                    let enter = try #require(keys.firstIndex(of: "ENTER"))
                    let rightControl = try #require(keys.firstIndex(of: position == .aboveEnter ? "SHIFT" : "BACKSPACE"))
                    #expect(abs(controls[symbols].width / controls[mode].width - 1.25 / 1.5) < 0.001)
                    #expect(abs(controls[settings].width / controls[mode].width - 1.25 / 1.5) < 0.001)
                    #expect(abs(controls[boundary - 1].width / controls[mode].width - 2 / 1.5) < 0.001)
                    #expect(abs(controls[boundary].width - controls[rightControl].width) < 0.001)
                    #expect(abs(controls[boundary].width - controls[enter].width) < 0.001)
                    #expect(controls[boundary - 1].maxX < controls[boundary].minX)
                    #expect(controls.allSatisfy { $0.height == 44 })
                }
            }
        }
    }

    private func expectBalancedSlots(_ frames: [CGRect], splitIndex: Int,
                                      width: Double, height: Double) {
        #expect(splitIndex == 6 && frames.count == splitIndex * 2)
        guard frames.count == splitIndex * 2, let first = frames.first else { return }
        #expect(frames.allSatisfy { abs($0.width - first.width) < 0.001 && $0.height == height })
        #expect(frames.prefix(splitIndex).allSatisfy { $0.minX >= 0 && $0.maxX < width / 2 })
        #expect(frames.suffix(splitIndex).allSatisfy { $0.minX > width / 2 && $0.maxX <= width + 0.001 })
        #expect(abs(frames[splitIndex - 1].maxX + frames[splitIndex].minX - width) < 0.001)
    }
}
