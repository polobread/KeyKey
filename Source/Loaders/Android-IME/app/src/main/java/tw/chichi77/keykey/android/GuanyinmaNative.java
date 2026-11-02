/* Copyright (c) 2026 Chui-Ping Cheng. MIT License. */
package tw.chichi77.keykey.android;

import java.nio.ByteBuffer;
import java.nio.CharBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.Objects;
import java.util.function.Predicate;

/** Thin UTF-8/ownership transport for the shared, platform-neutral C ABI. */
public final class GuanyinmaNative implements AutoCloseable {
    static {
        String path = System.getProperty("keykey.guanyinma.library");
        if (path == null || path.isEmpty()) System.loadLibrary("keykey_guanyinma");
        else System.load(path);
    }

    private long handle;

    private GuanyinmaNative(long handle) { this.handle = handle; }

    public static GuanyinmaNative open(String modelPath, String configJson,
                                      Predicate<String> glyph) {
        return new GuanyinmaNative(nativeOpen(utf8(modelPath), utf8(configJson), glyph));
    }

    public synchronized String apply(String operationJson) {
        return decodeUtf8(nativeRead(requireOpen(), 0, utf8(operationJson)));
    }

    public synchronized String snapshot() {
        return decodeUtf8(nativeRead(requireOpen(), 1, null));
    }

    public synchronized String userData() {
        return decodeUtf8(nativeRead(requireOpen(), 2, null));
    }

    @Override public synchronized void close() {
        if (handle != 0) {
            nativeClose(handle);
            handle = 0;
        }
    }

    private long requireOpen() {
        if (handle == 0) throw new IllegalStateException("Guanyinma session is closed");
        return handle;
    }

    private static byte[] utf8(String text) {
        Objects.requireNonNull(text, "UTF-8 text");
        try {
            ByteBuffer bytes = StandardCharsets.UTF_8.newEncoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).encode(CharBuffer.wrap(text));
            byte[] result = new byte[bytes.remaining()];
            bytes.get(result);
            return result;
        } catch (CharacterCodingException error) {
            throw new IllegalArgumentException("Guanyinma text contains invalid Unicode", error);
        }
    }

    // JNI calls this with standard UTF-8 bytes too; NewStringUTF/modified UTF-8
    // cannot preserve supplementary-plane candidates and must not be used.
    private static String decodeUtf8(byte[] bytes) {
        return new String(bytes, StandardCharsets.UTF_8);
    }

    private static native long nativeOpen(byte[] modelPath, byte[] configJson,
                                           Predicate<String> glyph);
    private static native byte[] nativeRead(long handle, int operation, byte[] input);
    private static native void nativeClose(long handle);
}
