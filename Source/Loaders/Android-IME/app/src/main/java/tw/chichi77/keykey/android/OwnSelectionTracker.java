package tw.chichi77.keykey.android;

import java.util.ArrayDeque;

/** Ordered, unacknowledged selection intentions for one host connection epoch. */
final class OwnSelectionTracker {
    enum Match { NO_MATCH, CURRENT, SUPERSEDED }

    record Anchor(int start, int end) {
        static Anchor fromFullSnapshot(int offset, int textLength, int partialStart, int partialEnd,
                int selectionStart, int selectionEnd) {
            if (offset < 0 || textLength < 0 || partialStart >= 0 || partialEnd >= 0
                    || selectionStart < 0 || selectionEnd < 0
                    || selectionStart > textLength || selectionEnd > textLength
                    || (long) offset + selectionStart > Integer.MAX_VALUE
                    || (long) offset + selectionEnd > Integer.MAX_VALUE) return null;
            // Android selections can legitimately run backwards; keep direction.
            return new Anchor(offset + selectionStart, offset + selectionEnd);
        }
    }

    static final class Token {
        final int selectionStart;
        final int selectionEnd;
        final int markedStart;
        final int markedEnd;
        final int relativeLength;
        final long sequence;

        private Token(int selectionStart, int selectionEnd, int markedStart, int markedEnd,
                int relativeLength, long sequence) {
            this.selectionStart = selectionStart;
            this.selectionEnd = selectionEnd;
            this.markedStart = markedStart;
            this.markedEnd = markedEnd;
            this.relativeLength = relativeLength;
            this.sequence = sequence;
        }

        private boolean matches(int start, int end, int candidateStart, int candidateEnd) {
            if (relativeLength >= 0) return candidateStart >= 0 && candidateEnd >= candidateStart
                    && (long) candidateEnd - candidateStart == relativeLength
                    && start == candidateEnd && end == candidateEnd;
            return selectionStart == start && selectionEnd == end
                    && markedStart == candidateStart && markedEnd == candidateEnd;
        }
    }

    static final class Batch {
        final long epoch;
        final long sequence;
        final int selectionStart, selectionEnd, markedStart, markedEnd;

        private Batch(long epoch, long sequence, int start, int end, int markedStart, int markedEnd) {
            this.epoch = epoch;
            this.sequence = sequence;
            this.selectionStart = start;
            this.selectionEnd = end;
            this.markedStart = markedStart;
            this.markedEnd = markedEnd;
        }
    }

    private final int capacity;
    private long sequence;
    private long epoch;
    private final ArrayDeque<Token> pending;

    OwnSelectionTracker() { this(256); }

    OwnSelectionTracker(int capacity) {
        if (capacity < 1) throw new IllegalArgumentException("capacity must be positive");
        this.capacity = capacity;
        pending = new ArrayDeque<>(capacity);
    }

    /** Unknown coordinates cannot establish ownership. Reversed selections are valid. */
    Token record(int start, int end, int markedStart, int markedEnd) {
        if (start < 0 || end < 0 || !((markedStart == -1 && markedEnd == -1)
                || (markedStart >= 0 && markedEnd >= markedStart))) return null;
        return append(new Token(start, end, markedStart, markedEnd, -1, ++sequence));
    }

    /** Resolve an initially unknown absolute anchor only from a real marked-end callback. */
    Token recordUnknownComposing(int utf16Length) {
        if (utf16Length <= 0) return null;
        return append(new Token(-1, -1, -2, -2, utf16Length, ++sequence));
    }

    private Token append(Token token) {
        if (pending.size() == capacity) pending.removeFirst();
        pending.addLast(token);
        return token;
    }

    Batch beginBatch(int start, int end, int markedStart, int markedEnd) {
        return new Batch(epoch, sequence, start, end, markedStart, markedEnd);
    }

    /** A net no-op batch may produce no TextView acknowledgement at all. */
    void finishBatch(Batch batch, int start, int end, int markedStart, int markedEnd) {
        if (batch.epoch != epoch || start < 0 || end < 0
                || !((markedStart == -1 && markedEnd == -1) || (markedStart >= 0 && markedEnd >= markedStart))) return;
        if (batch.selectionStart == start && batch.selectionEnd == end
                && batch.markedStart == markedStart && batch.markedEnd == markedEnd) {
            pending.removeIf(token -> token.sequence > batch.sequence);
        }
    }

    /** A rejected operation must not acknowledge another accepted operation. */
    void reject(Token token) {
        if (token != null) pending.removeIf(candidate -> candidate == token);
    }

    Match consume(int start, int end, int markedStart, int markedEnd) {
        Token matched = null;
        // The host may coalesce equal or intermediate batch updates. Prefer the
        // latest matching intent so no duplicate history survives its ACK.
        for (Token token : pending) {
            if (token.matches(start, end, markedStart, markedEnd)) matched = token;
        }
        if (matched == null) return Match.NO_MATCH;
        while (pending.removeFirst() != matched) { /* discard coalesced older intents */ }
        return pending.isEmpty() ? Match.CURRENT : Match.SUPERSEDED;
    }

    void clear() { pending.clear(); epoch++; }

    int pendingCount() { return pending.size(); }

    long epoch() { return epoch; }
}
