#!/usr/bin/env python3
"""Run the production candidate/composition button in a small UIKit Simulator app.

Requires an explicitly selected, booted iOS Simulator. No product app, engine,
keyboard preference, or Xcode project is changed. Source declarations are read
from the working tree on every run; there is no second renderer implementation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import platform
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[4]
IOS = ROOT / "Source/Loaders/iOS-Keyboard"
BUTTON_SOURCE = IOS / "Keyboard/KeyboardView.swift"
FONT_SOURCE = IOS / "KeyKeyEngine/Sources/KeyKeyEngine/KeyboardLayoutProfile.swift"
BUNDLE_ID = "io.github.polobread.keykey.strip-rendering-tests"


def declaration(source: str, marker: str) -> str:
    """Copy one complete production declaration, including its nested bodies."""
    if source.count(marker) != 1:
        raise ValueError(f"Expected one production declaration: {marker}")
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    cursor = opening + 1
    while depth:
        if cursor == len(source):
            raise ValueError(f"Unclosed production declaration: {marker}")
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[start:cursor]


def run(*args: str, **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(args, check=True, text=True, **kwargs)


SWIFT_TESTS = r'''
import QuartzCore

// This extension observes the actual production instance. Retain the native
// UILabel before layout: reading UIButton.titleLabel again can itself update
// its hidden state and conceal this regression from the test.
private extension KeyboardStripButton {
    func retainedLabels() -> [UILabel] { [titleLabel!, primaryLabel, indexLabel] }
}

@MainActor
private final class StripRenderingChecks {
    let container: UIView
    var results = [[String: Any]]()
    init(container: UIView) { self.container = container }

    func inkPixels(_ button: UIView) -> Int {
        let width = max(1, Int(button.bounds.width))
        let height = max(1, Int(button.bounds.height))
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            button.layer.render(in: context)
            let data = bytes.bindMemory(to: UInt8.self)
            return stride(from: 0, to: data.count, by: 4).reduce(0) { total, offset in
                total + (min(data[offset], data[offset + 1], data[offset + 2]) < 220 ? 1 : 0)
            }
        }
    }

    func configure(_ button: KeyboardStripButton, text: String,
                   role: String, font: KeyboardKeyFontSize) {
        if role == "candidate" {
            let attributed = text.isEmpty ? nil : NSAttributedString(
                string: text + "\n1", attributes: [.font: UIFont.systemFont(ofSize: 18),
                                                    .foregroundColor: UIColor.black])
            button.setAttributedTitle(attributed, for: .normal)
        } else {
            button.setTitle(text, for: .normal)
        }
        button.configureText(primary: text,
            index: role == "candidate" && !text.isEmpty ? "1" : nil,
            fontSize: font, baseSize: 18, indexSize: 10,
            primaryColor: .black, indexColor: .black)
        button.setNeedsLayout()
        button.layoutIfNeeded()
    }

    func check(_ button: KeyboardStripButton, labels: [UILabel],
               empty: Bool, name: String, failures: inout [String], samples: inout [[String: Any]]) async {
        try? await Task.sleep(nanoseconds: UInt64(RENDER_SETTLE_MS) * 1_000_000)
        let visible = labels.filter { !$0.isHidden && $0.alpha > 0 && !($0.text ?? "").isEmpty }
        let ink = inkPixels(button)
        samples.append(["step": name, "expectedEmpty": empty, "inkPixels": ink,
                        "visibleText": visible.map { $0.text ?? "" }])
        if empty && (!visible.isEmpty || ink != 0) {
            failures.append("\(name): empty cell has visible labels=\(visible.map { $0.text ?? "" }), ink=\(ink)")
        }
        if !empty && (visible.isEmpty || ink == 0) {
            let details = button.subviews.compactMap { $0 as? UILabel }.map { "text=\($0.text ?? "nil"),hidden=\($0.isHidden),alpha=\($0.alpha),frame=\($0.frame)" }
            failures.append("\(name): nonempty cell has no visible text (ink=\(ink), labels=\(details))")
        }
    }

    func scenario(role: String, enabled: Bool, from: KeyboardKeyFontSize,
                  to: KeyboardKeyFontSize) async {
        let button = KeyboardStripButton(type: .system)
        button.frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        button.backgroundColor = .white
        button.setTitleColor(.black, for: .normal)
        button.setTitleColor(.black, for: .disabled)
        button.titleLabel?.font = .systemFont(ofSize: 18)
        button.isEnabled = enabled
        container.addSubview(button)
        let labels = button.retainedLabels()
        var failures = [String]()
        var samples = [[String: Any]]()
        configure(button, text: "ㄛ", role: role, font: from)
        await check(button, labels: labels, empty: false, name: "insert", failures: &failures, samples: &samples)
        configure(button, text: "ㄛ", role: role, font: to)
        await check(button, labels: labels, empty: false, name: "font-switch", failures: &failures, samples: &samples)
        configure(button, text: "", role: role, font: to)
        await check(button, labels: labels, empty: true, name: "clear", failures: &failures, samples: &samples)
        // Re-layout the same empty cell at wide and tall bounds. This tests
        // renderer layout invalidation, not actual device rotation behavior.
        for size in [CGSize(width: 160, height: 32), CGSize(width: 100, height: 50)] {
            button.bounds.size = size
            button.setNeedsLayout()
            button.layoutIfNeeded()
            await check(button, labels: labels, empty: true, name: "empty-relayout", failures: &failures, samples: &samples)
        }
        configure(button, text: "ㄅ", role: role, font: to)
        await check(button, labels: labels, empty: false, name: "reinsert", failures: &failures, samples: &samples)
        configure(button, text: "", role: role, font: to)
        await check(button, labels: labels, empty: true, name: "clear-again", failures: &failures, samples: &samples)
        results.append(["role": role, "enabled": enabled, "fromFont": from.rawValue,
                        "toFont": to.rawValue, "passed": failures.isEmpty, "failures": failures, "samples": samples])
        button.removeFromSuperview()
    }

    func run() async -> [[String: Any]] {
        for role in ["composition", "candidate"] {
            for enabled in [true, false] {
                for font in KeyboardKeyFontSize.allCases {
                    await scenario(role: role, enabled: enabled, from: font, to: font)
                }
                for font in KeyboardKeyFontSize.allCases where font != .normal {
                    await scenario(role: role, enabled: enabled, from: .normal, to: font)
                    await scenario(role: role, enabled: enabled, from: font, to: .normal)
                }
            }
        }
        return results
    }
}

@main
private final class RenderingTestApplication: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let controller = UIViewController()
        controller.view.backgroundColor = .white
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        Task { @MainActor in
            let checks = StripRenderingChecks(container: controller.view)
            let cases = await checks.run()
            let failed = cases.filter { $0["passed"] as? Bool != true }.count
            let report: [String: Any] = ["runToken": RUN_TOKEN, "cases": cases,
                "caseCount": cases.count, "failedCount": failed, "settleMilliseconds": RENDER_SETTLE_MS,
                "systemVersion": UIDevice.current.systemVersion,
                "scope": "Actual production UIKit button rendering; no engine or input-host integration"]
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("strip-rendering-report.json")
            do {
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: url, options: .atomic)
                print("STRIP_RENDERING cases=\(cases.count) failed=\(failed)")
                fflush(stdout)
                exit(failed == 0 ? 0 : 1)
            } catch {
                fputs("Could not write rendering report: \(error)\n", stderr)
                exit(2)
            }
        }
        return true
    }
}
'''


def execute(source: Path, output: Path, device: str) -> dict:
    output.mkdir(parents=True, exist_ok=True)
    source_bytes = source.read_bytes()
    font_bytes = FONT_SOURCE.read_bytes()
    button_text = source_bytes.decode()
    font_text = font_bytes.decode()
    extracted = [declaration(font_text, "public enum KeyboardKeyFontSize:"),
                 "@MainActor\n" + declaration(button_text, "private enum KeyboardTextFitting {"),
                 "@MainActor\n" + declaration(button_text, "private final class KeyboardStripButton:")]
    token = str(uuid.uuid4())
    generated = "import UIKit\n" + "\n\n".join(extracted) + "\nlet RUN_TOKEN = " + json.dumps(token) + "\nlet RENDER_SETTLE_MS = 350\n" + SWIFT_TESTS
    swift = output / "StripRendering.swift"
    swift.write_text(generated)
    app = output / "KeyKeyStripRenderingTests.app"
    app.mkdir(exist_ok=True)
    executable = app / "KeyKeyStripRenderingTests"
    sdk = run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path", capture_output=True).stdout.strip()
    architecture = "arm64" if platform.machine() == "arm64" else "x86_64"
    with (output / "compile.log").open("w") as log:
        run("xcrun", "--sdk", "iphonesimulator", "swiftc", "-sdk", sdk, "-target", f"{architecture}-apple-ios17.0-simulator",
            "-module-cache-path", str(output / "ModuleCache"), "-parse-as-library",
            str(swift), "-framework", "UIKit", "-o", str(executable), stdout=log, stderr=subprocess.STDOUT)
    (app / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": BUNDLE_ID, "CFBundleName": "KeyKeyStripRenderingTests",
        "CFBundleExecutable": executable.name, "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
        "MinimumOSVersion": "17.0", "LSRequiresIPhoneOS": True,
        "UILaunchScreen": {}, "UIUserInterfaceStyle": "Light",
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft"]
    }))
    run("codesign", "--force", "--sign", "-", str(app), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    run("xcrun", "simctl", "install", device, str(app))
    # --console waits for this small application to finish; its exit is not the
    # result oracle because simctl versions differ in forwarding child status.
    with (output / "runtime.log").open("w") as log:
        launched = subprocess.run(["xcrun", "simctl", "launch", "--console", "--terminate-running-process",
                                   device, BUNDLE_ID], text=True, stdout=log, stderr=subprocess.STDOUT, timeout=300)
    container = Path(run("xcrun", "simctl", "get_app_container", device, BUNDLE_ID, "data", capture_output=True).stdout.strip())
    report = json.loads((container / "Documents/strip-rendering-report.json").read_text())
    if report["runToken"] != token:
        raise RuntimeError("Simulator returned a report from an earlier run")
    report.update({"source": str(source), "sourceSHA256": hashlib.sha256(source_bytes).hexdigest(),
                   "fontSourceSHA256": hashlib.sha256(font_bytes).hexdigest(),
                   "generatedSHA256": hashlib.sha256(swift.read_bytes()).hexdigest(),
                   "executableSHA256": hashlib.sha256(executable.read_bytes()).hexdigest(),
                   "runnerSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                   "device": device, "sdk": sdk, "simctlExitCode": launched.returncode})
    (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"{source.name}: {report['caseCount']} cases, {report['failedCount']} failed ({output / 'report.json'})")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="Explicit booted iOS Simulator UDID (not a real device)")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--negative-control", type=Path, help="Optional pre-fix KeyboardView.swift; must fail")
    args = parser.parse_args()
    output = args.output or Path(tempfile.mkdtemp(prefix="keykey-strip-rendering-"))
    devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json", capture_output=True).stdout)
    matches = [item for group in devices["devices"].values() for item in group if item["udid"] == args.device]
    if len(matches) != 1 or matches[0]["state"] != "Booted":
        parser.error("--device must identify one already booted, available Simulator")
    reports = {}
    if args.negative_control:
        reports["negativeControl"] = execute(args.negative_control.resolve(), output / "negative-control", args.device)
    reports["current"] = execute(BUTTON_SOURCE, output / "current", args.device)
    (output / "summary.json").write_text(json.dumps(reports, ensure_ascii=False, indent=2) + "\n")
    return 1 if reports["current"]["failedCount"] or (args.negative_control and reports["negativeControl"]["failedCount"] == 0) else 0


if __name__ == "__main__":
    raise SystemExit(main())
