import Carbon
import Foundation

guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
      let ptr = TISGetInputSourceProperty(current, kTISPropertyInputSourceID) else {
    fputs("Cannot read current input source\n", stderr)
    exit(1)
}
let sourceID = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
guard sourceID == "io.github.polobread.inputmethod.chichi77" else {
    fputs("Select 琦琦注音 before running the test; current source: \(sourceID)\n", stderr)
    exit(1)
}
print("Selected \(sourceID)")
