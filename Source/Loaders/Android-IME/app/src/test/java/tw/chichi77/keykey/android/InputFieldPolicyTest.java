package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.text.InputType;
import android.view.inputmethod.EditorInfo;

import org.junit.Test;

public final class InputFieldPolicyTest {
    @Test
    public void emailStartsInEnglishAndSkipsBopomofo() {
        InputFieldPolicy policy = InputFieldPolicy.fromValues(
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
                EditorInfo.IME_ACTION_NEXT);

        assertEquals(InputFieldPolicy.Kind.EMAIL, policy.kind());
        assertEquals(BopomofoEngine.InputMode.ENGLISH, policy.preferredMode());
        assertEquals("下一個", policy.enterLabel());
        assertEquals("數", policy.modeCaption(BopomofoEngine.InputMode.ENGLISH));
        assertFalse(policy.isKeyEnabled("SPACE", BopomofoEngine.InputMode.ENGLISH, false));
        assertFalse(policy.isKeyEnabled("EMOJI", BopomofoEngine.InputMode.ENGLISH, false));
        assertTrue(policy.isKeyEnabled("@", BopomofoEngine.InputMode.ENGLISH, false));
    }

    @Test
    public void decimalOnlyAllowsDecimalPointAndSignedMinusWhenRequested() {
        InputFieldPolicy unsigned = InputFieldPolicy.fromValues(
                InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL, 0);
        assertTrue(unsigned.isKeyEnabled(".", BopomofoEngine.InputMode.NUMBER, false));
        assertFalse(unsigned.isKeyEnabled("-", BopomofoEngine.InputMode.NUMBER, false));
        assertFalse(unsigned.isKeyEnabled("SHIFT", BopomofoEngine.InputMode.NUMBER, false));

        InputFieldPolicy signed = InputFieldPolicy.fromValues(
                InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL
                        | InputType.TYPE_NUMBER_FLAG_SIGNED, 0);
        assertTrue(signed.isKeyEnabled("-", BopomofoEngine.InputMode.NUMBER, false));
    }

    @Test
    public void supportedEditorActionsHaveLabelsAndNoEnterActionWins() {
        InputFieldPolicy done = policyWithAction(EditorInfo.IME_ACTION_DONE);
        assertEquals("完成", done.enterLabel());
        assertTrue(done.hasEditorAction());
        assertEquals("搜尋", policyWithAction(EditorInfo.IME_ACTION_SEARCH).enterLabel());
        assertEquals("傳送", policyWithAction(EditorInfo.IME_ACTION_SEND).enterLabel());
        assertEquals("前往", policyWithAction(EditorInfo.IME_ACTION_GO).enterLabel());
        assertEquals("上一個", policyWithAction(EditorInfo.IME_ACTION_PREVIOUS).enterLabel());
        InputFieldPolicy noAction = policyWithAction(EditorInfo.IME_ACTION_DONE
                | EditorInfo.IME_FLAG_NO_ENTER_ACTION);
        assertEquals("", noAction.enterLabel());
        assertFalse(noAction.hasEditorAction());
    }

    @Test
    public void customEditorActionUsesAppLabelAndId() {
        InputFieldPolicy policy = InputFieldPolicy.fromValues(InputType.TYPE_CLASS_TEXT,
                EditorInfo.IME_ACTION_UNSPECIFIED, "  送出\n表單  ", 42);

        assertTrue(policy.hasEditorAction());
        assertEquals(42, policy.editorAction());
        assertEquals("送出 表單", policy.enterLabel());

        InputFieldPolicy disabled = InputFieldPolicy.fromValues(InputType.TYPE_CLASS_TEXT,
                EditorInfo.IME_ACTION_DONE | EditorInfo.IME_FLAG_NO_ENTER_ACTION,
                "送出表單", 42);
        assertFalse(disabled.hasEditorAction());
        assertEquals("", disabled.enterLabel());
    }

    @Test
    public void androidFieldFamiliesMapToTheRequestedLayouts() {
        int[] generalVariations = {
                InputType.TYPE_TEXT_VARIATION_NORMAL,
                InputType.TYPE_TEXT_VARIATION_PERSON_NAME,
                InputType.TYPE_TEXT_VARIATION_POSTAL_ADDRESS,
                InputType.TYPE_TEXT_VARIATION_SHORT_MESSAGE,
                InputType.TYPE_TEXT_VARIATION_LONG_MESSAGE
        };
        for (int variation : generalVariations) {
            InputFieldPolicy policy = InputFieldPolicy.fromValues(
                    InputType.TYPE_CLASS_TEXT | variation, 0);
            assertEquals(InputFieldPolicy.Kind.GENERAL, policy.kind());
            assertEquals(BopomofoEngine.InputMode.BOPOMOFO, policy.preferredMode());
        }

        assertEquals(InputFieldPolicy.Kind.URL, InputFieldPolicy.fromValues(
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI, 0).kind());
        assertEquals(InputFieldPolicy.Kind.ASCII, InputFieldPolicy.fromValues(
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
                0).kind());
        assertEquals(InputFieldPolicy.Kind.PHONE, InputFieldPolicy.fromValues(
                InputType.TYPE_CLASS_PHONE, 0).kind());
        assertEquals(InputFieldPolicy.Kind.INTEGER, InputFieldPolicy.fromValues(
                InputType.TYPE_CLASS_NUMBER, 0).kind());
        assertEquals(InputFieldPolicy.Kind.DATE_TIME, InputFieldPolicy.fromValues(
                InputType.TYPE_CLASS_DATETIME | InputType.TYPE_DATETIME_VARIATION_DATE, 0).kind());
    }

    private InputFieldPolicy policyWithAction(int action) {
        return InputFieldPolicy.fromValues(InputType.TYPE_CLASS_TEXT, action);
    }
}
