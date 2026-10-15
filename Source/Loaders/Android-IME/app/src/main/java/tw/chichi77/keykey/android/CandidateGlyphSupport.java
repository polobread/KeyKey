package tw.chichi77.keykey.android;

import android.graphics.Paint;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.function.Predicate;

/** Process-local only: OS upgrades/restarts cannot retain stale missing-glyph results. */
final class CandidateGlyphSupport {
    private static final int MAX_ENTRIES = 4096;
    private final Predicate<String> probe;
    private final Map<String, Boolean> cache = new LinkedHashMap<>(64, 0.75f, true) {
        @Override protected boolean removeEldestEntry(Map.Entry<String, Boolean> entry) {
            return size() > MAX_ENTRIES;
        }
    };

    private static final class Shared {
        static final CandidateGlyphSupport INSTANCE = new CandidateGlyphSupport(nativeProbe());
    }

    static CandidateGlyphSupport shared() { return Shared.INSTANCE; }

    CandidateGlyphSupport(Predicate<String> probe) { this.probe = probe; }

    synchronized void reset() { cache.clear(); }

    synchronized boolean canDisplay(String text) {
        for (int start = 0; start < text.length();) {
            int end = CandidateDisplayText.nextGraphemeEnd(text, start);
            String cluster = text.substring(start, end);
            Boolean supported = cache.get(cluster);
            if (supported == null) {
                supported = probe.test(cluster);
                cache.put(cluster, supported);
            }
            if (!supported) return false;
            start = end;
        }
        return true;
    }

    private static Predicate<String> nativeProbe() {
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        paint.setTextSize(24);
        return cluster -> {
            if (paint.hasGlyph(cluster)) return true;
            // A missing ligature/IVS can still render as supported components.
            // Never call hasGlyph on a whole word: it asks for ONE ligature glyph.
            for (int offset = 0; offset < cluster.length();) {
                int cp = cluster.codePointAt(offset);
                offset += Character.charCount(cp);
                if (Character.isWhitespace(cp) || Character.getType(cp) == Character.FORMAT
                        || cp >= 0xFE00 && cp <= 0xFE0F || cp >= 0xE0100 && cp <= 0xE01EF) continue;
                if (!paint.hasGlyph(new String(Character.toChars(cp)))) return false;
            }
            return true;
        };
    }
}
