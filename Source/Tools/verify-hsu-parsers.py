#!/usr/bin/env python3
"""Compare mobile Hsu reading/editing with the macOS/Windows Formosa core.

Requires clang++, swiftc and javac/java (or JAVA_HOME). Builds only in a temporary
directory; does not change dictionaries, installed apps or user preferences.

From the repository root:
    JAVA_HOME="/path/to/jdk" python3 Source/Tools/verify-hsu-parsers.py

Checks final syllables and canonical dictionary keys after ambiguous sequences,
tones, invalid keys, backspaces and retyping against the actual shared C++ buffer.
"""
import itertools
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SWIFT = ROOT / "Source/Loaders/iOS-Keyboard/KeyKeyEngine/Sources/KeyKeyEngine"
JAVA = ROOT / "Source/Loaders/Android-IME/app/src/main/java/tw/chichi77/keykey/android"


def run(command, **kwargs):
    return subprocess.run(command, check=True, **kwargs)


def java_tool(name):
    home = os.environ.get("JAVA_HOME")
    return str(Path(home) / "bin" / name) if home else shutil.which(name) or name


def main():
    with tempfile.TemporaryDirectory(prefix="keykey-hsu-") as directory:
        work = Path(directory)
        cpp = work / "oracle.cpp"
        cpp.write_text(r'''
#include "Mandarin.h"
#include <iostream>
using namespace Formosa::Mandarin;
int main() {
    std::string line;
    while (std::getline(std::cin, line)) {
        BopomofoReadingBuffer reading(BopomofoKeyboardLayout::HsuLayout());
        for (char key : line) {
            if (key == '~') reading.backspace();
            else reading.combineKey(key);
        }
        std::cout << line << '\t' << reading.composedString() << '\t'
                  << reading.absoluteOrderQueryString() << '\n';
    }
}
''')
        run(["clang++", "-std=c++17", "-O2", "-Wno-parentheses", "-DMANDARIN_USE_MINIMAL_OPENVANILLA",
             "-I" + str(ROOT / "Source/Frameworks/Formosa/Headers"),
             "-I" + str(ROOT / "Source/Frameworks/OpenVanilla/Headers"),
             str(cpp), str(ROOT / "Source/Frameworks/Formosa/Source/Mandarin.cpp"),
             "-o", str(work / "oracle")])
        main_swift = work / "main.swift"
        main_swift.write_text(r'''
import Foundation
while let line = readLine() {
    var reading = BopomofoReading(layout: .hsu)
    for key in line {
        if key == "~" { reading.backspace() } else { reading.combine(key) }
    }
    print(line + "\t" + reading.displayText + "\t" + reading.queryKey)
}
''')
        run(["swiftc", "-O", *[str(SWIFT / name) for name in [
            "BopomofoSyllable.swift", "BopomofoReading.swift",
            "BopomofoKeyboardLayout.swift"]],
            str(main_swift), "-o", str(work / "swift-reader")])
        main_java = work / "HsuProbe.java"
        main_java.write_text(r'''
package tw.chichi77.keykey.android;
import java.io.*;
import java.nio.charset.StandardCharsets;
public class HsuProbe {
    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        String line;
        while ((line = input.readLine()) != null) {
            BopomofoReading reading = new BopomofoReading();
            reading.setLayout(BopomofoKeyboardLayout.HSU);
            for (char key : line.toCharArray()) {
                if (key == '~') reading.backspace(); else reading.combine(key);
            }
            System.out.println(line + "\t" + reading.displayText() + "\t" + reading.languageModelKey());
        }
    }
}
''')
        run([java_tool("javac"), "-encoding", "UTF-8", "-d", str(work),
             str(JAVA / "BopomofoReading.java"), str(JAVA / "BopomofoKeyboardLayout.java"),
             str(main_java)])

        keys = "bpmfdtnlgkhjvcrzasexuy iwo".replace(" ", "")
        sequences = {"", "~", "q", "myd", "myf", "myj", "mys", "jxl", "llf", "gef", "guf"}
        for size in (1, 2, 3):
            sequences.update(map("".join, itertools.product(keys, repeat=size)))
        sequences.update(map("".join, itertools.product(
            "bpmfdtnlgkhjvcrzas", "exu", "yhgeiawomnkl", "dfjs")))
        # Edits matter: desktop reconstructs the canonical sequence at every key.
        sequences = sorted({s + suffix for s in sequences for suffix in ("", "~", "~~", "~e", "#")})
        input_data = ("\n".join(sequences) + "\n").encode()
        expected = run([str(work / "oracle")], input=input_data, stdout=subprocess.PIPE).stdout
        for label, command in [
            ("Swift", [str(work / "swift-reader")]),
            ("Java", [java_tool("java"), "-cp", str(work), "tw.chichi77.keykey.android.HsuProbe"])
        ]:
            actual = run(command, input=input_data, stdout=subprocess.PIPE).stdout
            if actual != expected:
                mismatches = [(a, b) for a, b in itertools.zip_longest(
                    expected.decode().splitlines(), actual.decode().splitlines()) if a != b]
                raise AssertionError(f"{label}: {len(mismatches)} differences; first 10: {mismatches[:10]}")
            print(f"{label}: {len(sequences):,} Hsu input/edit cases match the macOS/Windows core")


if __name__ == "__main__":
    main()
