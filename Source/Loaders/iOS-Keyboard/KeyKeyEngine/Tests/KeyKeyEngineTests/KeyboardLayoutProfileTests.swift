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
                        let rows = profile.rows(orientation: orientation, plane: plane, shifted: shifted)
                        #expect(!rows.isEmpty)
                        for (index, row) in rows.enumerated() {
                            #expect(!row.isEmpty)
                            for width in [314.0, 446, 649, 820] {
                                let split = profile.splitGeometry
                                let expanded = split.map { width >= $0.minimumExpandedWidth } ?? false
                                let extraControl = expanded && (split?.punctuation.indices.contains(index) == true)
                                let splitIndex = split.map { expanded ? $0.expandedKeySplit : $0.keySplit }
                                let weights = Array(repeating: 1.0, count: row.count + (extraControl ? 1 : 0))
                                let frames = KeyboardRowGeometry.frames(width: width, height: 44,
                                    weights: weights, splitIndex: splitIndex, spacing: profile.keySpacing)
                                expectUsableFrames(frames, width: width, expectedCount: weights.count,
                                                   splitIndex: splitIndex)
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
                let expanded = split.map { width >= $0.minimumExpandedWidth } ?? false
                let compositionWeights = Array(repeating: 1.0,
                    count: profile.compositionCellCount + (expanded ? 1 : 0))
                let composition = KeyboardRowGeometry.frames(width: width, height: 44,
                    weights: compositionWeights, splitIndex: split?.compositionSplit,
                    spacing: profile.stripSpacing)
                expectUsableFrames(composition, width: width, expectedCount: compositionWeights.count,
                                   splitIndex: split?.compositionSplit)
                for globe in [false, true] {
                    var keys = profile.functionKeys
                    if split != nil, let space = keys.firstIndex(of: "SPACE") {
                        keys.insert("SPACE", at: space + 1)
                    }
                    if globe { keys.insert(KeyboardLayout.inputModeSwitchKey, at: 0) }
                    if expanded { keys.removeAll { split?.punctuation.contains($0) == true } }
                    #expect(!keys.isEmpty)
                    let weights = keys.map { profile.functionWeight(for: $0, expanded: expanded) }
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
        let baseline = KeyboardLayoutProfile.full
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

    @Test func eachRegisteredProfilePersistsByIdentifier() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let settings = KeyboardLayoutProfileSettings(defaults: defaults)
        for profile in KeyboardLayoutProfile.available {
            settings.setProfile(profile)
            #expect(defaults.string(forKey: "keyboardLayoutProfile") == profile.id)
            #expect(KeyboardLayoutProfileSettings(defaults: defaults).profile == profile)
        }
    }

    @Test func previousPresentationChoicesAreReadWithoutRewritingThem() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let legacyChoices: [(String, KeyboardLayoutProfile)] = [("full", .full), ("split", .split)]
        for (storedIdentifier, expectedProfile) in legacyChoices {
            defaults.set(storedIdentifier, forKey: "keyboardPresentation")
            #expect(KeyboardLayoutProfileSettings(defaults: defaults).profile == expectedProfile)
            #expect(defaults.string(forKey: "keyboardPresentation") == storedIdentifier)
            #expect(defaults.object(forKey: "keyboardLayoutProfile") == nil)
        }
    }

    @Test func currentProfilePreferenceWinsAndUnknownIdentifiersUseFull() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let settings = KeyboardLayoutProfileSettings(defaults: defaults)
        #expect(settings.profile == .full)
        defaults.set("split", forKey: "keyboardPresentation")
        settings.setProfile(.full)
        #expect(settings.profile == .full)
        defaults.set(UUID().uuidString, forKey: "keyboardLayoutProfile")
        #expect(settings.profile == .full)
    }

    private let defaultsSuiteName = "KeyboardLayoutProfileTests.\(UUID())"
    private func makeDefaults() -> UserDefaults { UserDefaults(suiteName: defaultsSuiteName)! }

    private func expectUsableFrames(_ frames: [CGRect], width: Double,
                                    expectedCount: Int, splitIndex: Int?) {
        #expect(frames.count == expectedCount)
        #expect(frames.allSatisfy {
            $0.width > 0 && $0.width.isFinite && $0.minX >= 0 && $0.maxX <= width + 0.001
        })
        for index in 1..<frames.count { #expect(frames[index - 1].maxX <= frames[index].minX + 0.001) }
        if let splitIndex {
            #expect(splitIndex > 0 && splitIndex < frames.count)
            guard splitIndex > 0 && splitIndex < frames.count else { return }
            #expect(frames[splitIndex - 1].maxX < width / 2)
            #expect(frames[splitIndex].minX > width / 2)
            #expect(abs(frames[splitIndex - 1].maxX + frames[splitIndex].minX - width) < 0.001)
        } else if let last = frames.last {
            #expect(abs(last.maxX - width) < 0.001)
        }
    }
}

/// Exact dimensions belong to this existing preset, not every registered profile.
@Suite("Existing split profile")
struct SplitKeyboardLayoutProfileTests {
    @Test func expandedPresetKeepsBalancedKeyAndCompositionSlots() throws {
        let profile = KeyboardLayoutProfile.split
        let split = try #require(profile.splitGeometry)
        for width in [600.0, 649, 795, 820] {
            let row = profile.rows(orientation: .portrait, plane: .bopomofo, shifted: false)[0]
            let keyFrames = KeyboardRowGeometry.frames(width: width, height: 49,
                weights: Array(repeating: 1, count: row.count + 1), splitIndex: split.expandedKeySplit,
                spacing: profile.keySpacing)
            #expect(keyFrames.count == 12)
            #expect(keyFrames.allSatisfy { abs($0.width - keyFrames[0].width) < 0.001 })
            #expect(keyFrames.prefix(6).allSatisfy { $0.maxX < width / 2 })
            #expect(keyFrames.suffix(6).allSatisfy { $0.minX > width / 2 })
            let composition = KeyboardRowGeometry.frames(width: width, height: 49,
                weights: Array(repeating: 1, count: profile.compositionCellCount + 1),
                splitIndex: split.compositionSplit, spacing: profile.stripSpacing)
            #expect(profile.compositionCellCount == 11)
            #expect(composition[10].maxX < composition[11].minX)
        }
    }

    @Test func expandedPresetPreservesItsApprovedFunctionKeyProportions() throws {
        let profile = KeyboardLayoutProfile.split
        let split = try #require(profile.splitGeometry)
        let baseKeys = ["MODE", "SYMBOL", "SETTINGS", "SPACE", "SPACE", "BACKSPACE", "ENTER"]
        for globe in [false, true] {
            let keys = (globe ? [KeyboardLayout.inputModeSwitchKey] : []) + baseKeys
            let boundary = try #require(keys.firstIndex(of: "SPACE")) + 1
            let controls = KeyboardRowGeometry.frames(width: split.minimumExpandedWidth, height: 49,
                weights: keys.map { profile.functionWeight(for: $0, expanded: true) },
                splitIndex: boundary, spacing: profile.keySpacing)
            let mode = try #require(keys.firstIndex(of: "MODE"))
            #expect(abs(controls[mode + 1].width / controls[mode].width - 1.25 / 1.5) < 0.001)
            #expect(abs(controls[mode + 3].width / controls[mode].width - 2 / 1.5) < 0.001)
            #expect(abs(controls[boundary].width - controls[boundary + 1].width) < 0.001)
            #expect(controls[boundary - 1].maxX < controls[boundary].minX)
        }
    }
}
