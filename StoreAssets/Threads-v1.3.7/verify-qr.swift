#!/usr/bin/env swift
// Decode the three QR codes from the finished image using macOS Vision.
import Foundation
import Vision

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let config = try JSONSerialization.jsonObject(with: Data(contentsOf: here.appendingPathComponent("design.json"))) as! [String: Any]
let expected = Set((config["downloads"] as! [[String: Any]]).map { $0["url"] as! String })
let request = VNDetectBarcodesRequest()
request.symbologies = [.qr]
try VNImageRequestHandler(url: here.appendingPathComponent("03-mobile-downloads.png"), options: [:]).perform([request])
let actual = Set((request.results ?? []).compactMap { $0.payloadStringValue })
guard actual == expected else {
    fputs("QR decode failed. Expected \(expected), got \(actual)\n", stderr)
    exit(1)
}
print("Verified all three QR codes in the finished 1080 × 1350 PNG:")
for url in actual.sorted() { print(url) }
