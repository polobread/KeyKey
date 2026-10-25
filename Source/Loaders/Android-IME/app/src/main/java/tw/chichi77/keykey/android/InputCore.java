package tw.chichi77.keykey.android;

/** Algorithm choice is independent of the keyboard's touch/physical profile. */
enum InputCore {
    JAVA("java", "Java（原核心）"), GUANYINMA("guanyinma", "Guanyinma（Rust）");
    final String rawName;
    final String displayName;
    InputCore(String rawName, String displayName) { this.rawName = rawName; this.displayName = displayName; }
    static InputCore fromRaw(String value) {
        for (InputCore core : values()) if (core.rawName.equals(value) || core.name().equals(value)) return core;
        return JAVA;
    }
}
