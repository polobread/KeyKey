package tw.chichi77.keykey.android;

import static org.junit.Assert.*;
import static tw.chichi77.keykey.android.OwnSelectionTracker.Match.*;

import org.junit.Test;

public final class OwnSelectionTrackerTest {
    @Test public void delayedRawReadingIsStillAnOwnAcknowledgement() throws Exception {
        OwnSelectionTracker tracker = new OwnSelectionTracker();
        tracker.record(1, 1, 0, 1);
        Thread.sleep(250); // Beyond the former frontend's 200 ms time guard.
        assertEquals(CURRENT, tracker.consume(1, 1, 0, 1));
    }

    @Test public void olderAcknowledgementCannotReplaceANewerPendingCaret() {
        OwnSelectionTracker tracker = new OwnSelectionTracker();
        tracker.record(1, 1, 0, 1);
        tracker.record(2, 2, 0, 2);
        assertEquals(SUPERSEDED, tracker.consume(1, 1, 0, 1));
        assertEquals(1, tracker.pendingCount());
        assertEquals(CURRENT, tracker.consume(2, 2, 0, 2));
    }

    @Test public void coalescedUpdateAcknowledgesEarlierUnreportedMutations() {
        OwnSelectionTracker tracker = new OwnSelectionTracker();
        tracker.record(1, 1, 0, 1);
        tracker.record(2, 2, 0, 2);
        tracker.record(3, 3, 0, 3);
        assertEquals(CURRENT, tracker.consume(3, 3, 0, 3));
        assertEquals(NO_MATCH, tracker.consume(1, 1, 0, 1));
        assertEquals(NO_MATCH, tracker.consume(2, 2, 0, 2));
    }

    @Test public void implicitMarkedEndAndExplicitMiddleCaretRemainSeparate() {
        OwnSelectionTracker tracker = new OwnSelectionTracker();
        tracker.record(14, 14, 10, 14);
        tracker.record(12, 12, 10, 14);
        assertEquals(SUPERSEDED, tracker.consume(14, 14, 10, 14));
        assertEquals(CURRENT, tracker.consume(12, 12, 10, 14));
    }

    @Test public void utf16OffsetsAndNonzeroAnchorMatchExactly() {
        OwnSelectionTracker tracker = new OwnSelectionTracker();
        int anchor = "前😀".length();
        int end = anchor + "請😀假".length();
        tracker.record(end, end, anchor, end);
        assertEquals(NO_MATCH, tracker.consume(end - 1, end - 1, anchor, end));
        assertEquals(NO_MATCH, tracker.consume(end, end, anchor + 1, end));
        assertEquals(CURRENT, tracker.consume(end, end, anchor, end));
    }

    @Test public void acknowledgedCaretHistoryDoesNotSwallowUserReturningThere() {
        OwnSelectionTracker tracker = new OwnSelectionTracker();
        tracker.record(5, 5, 2, 7);
        assertEquals(CURRENT, tracker.consume(5, 5, 2, 7));
        assertEquals(NO_MATCH, tracker.consume(5, 5, 2, 7));
    }

    @Test public void realCursorAndSelectionChangesDoNotMatchAnOwnMutation() {
        OwnSelectionTracker tracker = new OwnSelectionTracker();
        tracker.record(7, 7, 2, 7);
        assertEquals(NO_MATCH, tracker.consume(4, 4, 2, 7));
        assertEquals(NO_MATCH, tracker.consume(2, 5, 2, 7));
        assertEquals(NO_MATCH, tracker.consume(7, 7, -1, -1));
        assertEquals(CURRENT, tracker.consume(7, 7, 2, 7));
    }

    @Test public void clearSeparatesHostsAndOldRollbackCannotRemoveNewIntent() {
        OwnSelectionTracker tracker = new OwnSelectionTracker();
        var old = tracker.record(1, 1, 0, 1);
        tracker.clear();
        tracker.record(1, 1, 0, 1);
        tracker.reject(old);
        assertEquals(CURRENT, tracker.consume(1, 1, 0, 1));
        assertEquals(NO_MATCH, tracker.consume(1, 1, 0, 1));
    }

    @Test public void rejectionRestoresThePreviousAcceptedPendingIntent() {
        OwnSelectionTracker tracker = new OwnSelectionTracker();
        tracker.record(3, 3, 0, 3);
        var rejected = tracker.record(1, 1, 0, 3);
        tracker.reject(rejected);
        assertEquals(NO_MATCH, tracker.consume(1, 1, 0, 3));
        assertEquals(CURRENT, tracker.consume(3, 3, 0, 3));
    }

    @Test public void duplicateIntentAckLeavesNoHistoryForAUserMove() {
        OwnSelectionTracker tracker = new OwnSelectionTracker();
        tracker.record(2, 2, 0, 2);
        tracker.record(2, 2, 0, 2);
        assertEquals(CURRENT, tracker.consume(2, 2, 0, 2));
        assertEquals(NO_MATCH, tracker.consume(2, 2, 0, 2));
    }

    @Test public void pendingStorageIsBoundedAndEvictedRollbackIsHarmless() {
        OwnSelectionTracker tracker = new OwnSelectionTracker(3);
        var evicted = tracker.record(1, 1, 0, 1);
        tracker.record(2, 2, 0, 2);
        tracker.record(3, 3, 0, 3);
        tracker.record(4, 4, 0, 4);
        assertEquals(3, tracker.pendingCount());
        tracker.reject(evicted);
        assertEquals(NO_MATCH, tracker.consume(1, 1, 0, 1));
        assertEquals(SUPERSEDED, tracker.consume(3, 3, 0, 3));
        assertEquals(CURRENT, tracker.consume(4, 4, 0, 4));
    }

    @Test public void unknownCoordinatesAreNotGuessedAndReversedRangesAreValid() {
        OwnSelectionTracker tracker = new OwnSelectionTracker();
        assertNull(tracker.record(-1, -1, 0, 1));
        assertNull(tracker.record(1, 1, -1, 1));
        assertEquals(0, tracker.pendingCount());
        tracker.record(7, 3, -1, -1);
        assertEquals(CURRENT, tracker.consume(7, 3, -1, -1));
    }
    @Test public void unknownFirstCompositionLearnsOnlyAnActualMarkedEnd() {
        OwnSelectionTracker tracker = new OwnSelectionTracker();
        tracker.recordUnknownComposing(3);
        assertEquals(NO_MATCH, tracker.consume(102, 102, 100, 103));
        assertEquals(NO_MATCH, tracker.consume(99, 99, 100, 103));
        assertEquals(NO_MATCH, tracker.consume(100, 103, 100, 103));
        assertEquals(NO_MATCH, tracker.consume(103, 103, 99, 103));
        assertEquals(CURRENT, tracker.consume(103, 103, 100, 103));
        assertEquals(NO_MATCH, tracker.consume(103, 103, 100, 103));
    }

    @Test public void unknownCoalescedAndUnchangedSelectionStillAcknowledgeMarkedSpan() {
        OwnSelectionTracker tracker = new OwnSelectionTracker();
        tracker.recordUnknownComposing(1);
        tracker.recordUnknownComposing(2);
        assertEquals(SUPERSEDED, tracker.consume(1, 1, 0, 1));
        // No old-selection delta is needed: the actual marked range proves it.
        assertEquals(CURRENT, tracker.consume(2, 2, 0, 2));
    }

    @Test public void batchReturningToTheOriginalMiddleCaretCannotSwallowTheNextUserMove() {
        OwnSelectionTracker tracker = new OwnSelectionTracker();
        BatchEditor editor = new BatchEditor(tracker, 1, 1, 0, 4, false);
        editor.begin();
        editor.compose(4);
        editor.select(1);
        editor.end();
        assertEquals(0, editor.callbacks);
        assertEquals(0, tracker.pendingCount());
        assertEquals(NO_MATCH, tracker.consume(4, 4, 0, 4)); // actual user tap at end
    }

    @Test public void batchNoopDoesNotResurrectAlreadyAcknowledgedReentrantIntents() {
        OwnSelectionTracker tracker = new OwnSelectionTracker();
        BatchEditor editor = new BatchEditor(tracker, 1, 1, 0, 4, true);
        editor.begin();
        editor.compose(4);
        editor.select(1);
        editor.end();
        assertEquals(2, editor.callbacks);
        assertEquals(0, tracker.pendingCount());
        assertEquals(NO_MATCH, tracker.consume(4, 4, 0, 4));
    }

    @Test public void noOpBatchOnlyDiscardsItsOwnNewIntentsAndHonorsEpochClear() {
        OwnSelectionTracker tracker = new OwnSelectionTracker();
        tracker.record(2, 2, 0, 2);
        var batch = tracker.beginBatch(1, 1, 0, 4);
        tracker.record(4, 4, 0, 4);
        tracker.record(1, 1, 0, 4);
        tracker.finishBatch(batch, 1, 1, 0, 4);
        assertEquals(CURRENT, tracker.consume(2, 2, 0, 2));
        var oldEpoch = tracker.beginBatch(1, 1, -1, -1);
        tracker.clear();
        tracker.record(1, 1, -1, -1);
        tracker.finishBatch(oldEpoch, 1, 1, -1, -1);
        assertEquals(CURRENT, tracker.consume(1, 1, -1, -1));
    }

    @Test public void rejectionAfterAReentrantAckCannotResurrectCoalescedHistory() {
        OwnSelectionTracker tracker = new OwnSelectionTracker();
        tracker.record(1, 1, 0, 1);
        var completed = tracker.record(2, 2, 0, 2);
        assertEquals(CURRENT, tracker.consume(2, 2, 0, 2));
        tracker.record(3, 3, 0, 3);
        tracker.reject(completed);
        assertEquals(NO_MATCH, tracker.consume(1, 1, 0, 1));
        assertEquals(CURRENT, tracker.consume(3, 3, 0, 3));
    }

    @Test public void fullLengthLegalCompositionCanWaitForCoalescedAcknowledgements() {
        OwnSelectionTracker tracker = new OwnSelectionTracker();
        // Twenty syllables, at most five keys and two caret operations per key.
        for (int position = 1; position <= 200; position++) tracker.record(position, position, 0, position);
        assertEquals(200, tracker.pendingCount());
        assertEquals(SUPERSEDED, tracker.consume(1, 1, 0, 1));
        assertEquals(CURRENT, tracker.consume(200, 200, 0, 200));
    }

    @Test public void initialSnapshotAcceptsUtf16OffsetsAndLegitimateReverseSelections() {
        assertEquals(new OwnSelectionTracker.Anchor(0, 0),
                OwnSelectionTracker.Anchor.fromFullSnapshot(0, 0, -1, -1, 0, 0));
        assertEquals(new OwnSelectionTracker.Anchor(0, 0),
                OwnSelectionTracker.Anchor.fromFullSnapshot(0, 3, -1, 0, 0, 0));
        assertEquals(new OwnSelectionTracker.Anchor(5, 5),
                OwnSelectionTracker.Anchor.fromFullSnapshot(0, 5, -1, 5, 5, 5));
        String text = "前😀甲乙後";
        var reverse = OwnSelectionTracker.Anchor.fromFullSnapshot(10, text.length(), -1, -1, 5, 3);
        assertEquals(new OwnSelectionTracker.Anchor(15, 13), reverse);
        assertEquals(13, Math.min(reverse.start(), reverse.end()));
    }

    @Test public void initialSnapshotNeverInventsAnAnchorFromPartialOrInvalidCoordinates() {
        for (int[] input : new int[][]{{0,-1,-1,-1,0,0}, {-1,3,-1,-1,0,0}, {0,3,0,0,0,0},
                {0,3,0,3,0,0}, {0,3,-1,-1,-1,0}, {0,3,-1,-1,4,4}, {Integer.MAX_VALUE,3,-1,-1,1,1}}) {
            assertNull(OwnSelectionTracker.Anchor.fromFullSnapshot(input[0],input[1],input[2],input[3],input[4],input[5]));
        }
    }

    @Test public void rejectedBatchRetainsEachDelayedIntermediateAcknowledgement() {
        OwnSelectionTracker tracker = new OwnSelectionTracker();
        BatchEditor editor = new BatchEditor(tracker, 1, 1, 0, 4, false, false);
        assertFalse(editor.begin());
        editor.compose(4);
        editor.select(1);
        editor.end();
        assertEquals(0, editor.callbacks);
        assertEquals(2, tracker.pendingCount());
        // This legal host did not batch: it later reports each accepted write,
        // even though the final tuple returned to the original middle caret.
        assertEquals(java.util.List.of(SUPERSEDED, CURRENT), editor.flushDeferred());
        assertEquals(2, editor.callbacks);
        assertEquals(NO_MATCH, tracker.consume(4, 4, 0, 4));
    }

    /** Stateful batch host: unchanged final tuples send no deferred ACK. */
    private static final class BatchEditor {
        final OwnSelectionTracker tracker;
        final boolean reentrant;
        final boolean acceptsBatch;
        final java.util.List<int[]> deferred = new java.util.ArrayList<>();
        int start, end, markedStart, markedEnd, callbacks;
        int initialStart, initialEnd, initialMarkedStart, initialMarkedEnd;
        OwnSelectionTracker.Batch batch;

        BatchEditor(OwnSelectionTracker tracker, int start, int end, int markedStart, int markedEnd, boolean reentrant) {
            this(tracker, start, end, markedStart, markedEnd, reentrant, true);
        }
        BatchEditor(OwnSelectionTracker tracker, int start, int end, int markedStart, int markedEnd,
                boolean reentrant, boolean acceptsBatch) {
            this.tracker = tracker; this.reentrant = reentrant; this.acceptsBatch = acceptsBatch;
            this.start = start; this.end = end; this.markedStart = markedStart; this.markedEnd = markedEnd;
        }
        boolean begin() {
            initialStart = start; initialEnd = end; initialMarkedStart = markedStart; initialMarkedEnd = markedEnd;
            batch = tracker.beginBatch(start, end, markedStart, markedEnd);
            return acceptsBatch;
        }
        void compose(int length) {
            tracker.record(markedStart + length, markedStart + length, markedStart, markedStart + length);
            markedEnd = markedStart + length; start = end = markedEnd;
            if (reentrant) acknowledge();
            else if (!acceptsBatch) deferred.add(new int[]{start, end, markedStart, markedEnd});
        }
        void select(int caret) {
            tracker.record(caret, caret, markedStart, markedEnd); start = end = caret;
            if (reentrant) acknowledge();
            else if (!acceptsBatch) deferred.add(new int[]{start, end, markedStart, markedEnd});
        }
        void end() {
            if (!acceptsBatch) return;
            if (!reentrant && (start != initialStart || end != initialEnd
                    || markedStart != initialMarkedStart || markedEnd != initialMarkedEnd)) acknowledge();
            tracker.finishBatch(batch, start, end, markedStart, markedEnd);
        }
        java.util.List<OwnSelectionTracker.Match> flushDeferred() {
            var matches = new java.util.ArrayList<OwnSelectionTracker.Match>();
            for (int[] tuple : deferred) {
                matches.add(tracker.consume(tuple[0], tuple[1], tuple[2], tuple[3])); callbacks++;
            }
            deferred.clear();
            return matches;
        }
        void acknowledge() { callbacks++; assertNotEquals(NO_MATCH, tracker.consume(start, end, markedStart, markedEnd)); }
    }

}
