package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class TouchSmartHostTextStateTest {
    @Test
    public void overflowCommitsPrefixAndBackspaceOnlyChangesTail() {
        TouchSmartHostTextState state = new TouchSmartHostTextState();
        assertEquals(new TouchSmartHostTextState.Edit(0, "請假要去哪裡玩呢去"),
                state.update("請假要去哪裡玩呢去", ""));
        assertEquals(new TouchSmartHostTextState.Edit(0, "海"),
                state.update("要去哪裡玩呢去海", "請假"));
        assertEquals("要去哪裡玩呢去海", state.editableText());
        assertEquals(new TouchSmartHostTextState.Edit(1, ""),
                state.update("要去哪裡玩呢去", ""));
        assertEquals(new TouchSmartHostTextState.Edit(0, "海"),
                state.update("要去哪裡玩呢去海", ""));
        assertTrue(state.finish("要去哪裡玩呢去海").isEmpty());
    }

    @Test
    public void middleCandidateReplacesOnlyEditableSuffix() {
        TouchSmartHostTextState state = new TouchSmartHostTextState();
        state.update("請假要去哪裡玩呢去", "");
        state.update("要去哪裡玩呢去海", "請假");
        assertEquals(new TouchSmartHostTextState.Edit(4, "完呢去海"),
                state.update("要去哪裡完呢去海", ""));
        assertEquals("要去哪裡完呢去海", state.editableText());
    }

    @Test
    public void resetForNewFieldDoesNotDeleteTextAlreadyInOldField() {
        TouchSmartHostTextState state = new TouchSmartHostTextState();
        state.update("請假", "");
        state.reset();
        assertEquals(new TouchSmartHostTextState.Edit(0, "海"), state.update("海", ""));
    }

    @Test
    public void unicodeDifferenceUsesUtf16DeletionLength() {
        TouchSmartHostTextState state = new TouchSmartHostTextState();
        state.update("玩😀呢", "");
        assertEquals(new TouchSmartHostTextState.Edit(3, "完呢"),
                state.update("玩完呢", ""));
    }
}
