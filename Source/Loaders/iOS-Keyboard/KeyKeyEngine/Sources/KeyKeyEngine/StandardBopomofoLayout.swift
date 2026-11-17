// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
/// Key captions and event classification for the standard Bopomofo frontend.
public enum StandardBopomofoLayout {
    static let glyphs = "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙㄧㄨㄩㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦˊˇˋ˙"
    private static let glyphForKey = Dictionary(uniqueKeysWithValues: zip(
        "1qaz2wsxedcrfv5tgbyhnujm8ik,9ol.0p;/-6347", glyphs
    ))
    public static func glyph(for key: Character) -> Character? { glyphForKey[key] }
    public static func isToneKey(_ key: Character) -> Bool { "6347".contains(key) }
    public static func isReadingKey(_ key: Character) -> Bool {
        glyphForKey[Character(key.lowercased())] != nil
    }
}
