package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.text.InputType;
import android.view.inputmethod.EditorInfo;

import org.junit.Test;

public final class InputFieldPolicyTest {
    @Test
    public void generalTextAndUrlStartWithEveryModeAvailable() {
        int[] fullTextVariations = {
                InputType.TYPE_TEXT_VARIATION_NORMAL,
                InputType.TYPE_TEXT_VARIATION_URI,
                InputType.TYPE_TEXT_VARIATION_EMAIL_SUBJECT,
                InputType.TYPE_TEXT_VARIATION_SHORT_MESSAGE,
                InputType.TYPE_TEXT_VARIATION_LONG_MESSAGE,
                InputType.TYPE_TEXT_VARIATION_PERSON_NAME,
                InputType.TYPE_TEXT_VARIATION_POSTAL_ADDRESS,
                InputType.TYPE_TEXT_VARIATION_WEB_EDIT_TEXT,
                InputType.TYPE_TEXT_VARIATION_FILTER,
                InputType.TYPE_TEXT_VARIATION_PHONETIC
        };

        for (int variation : fullTextVariations) {
            InputFieldPolicy policy = InputFieldPolicy.fromValues(
                    InputType.TYPE_CLASS_TEXT | variation, EditorInfo.IME_ACTION_NEXT);

            if (variation == InputType.TYPE_TEXT_VARIATION_URI) {
                assertEquals(InputFieldPolicy.Kind.URL, policy.kind());
            } else {
                assertEquals(InputFieldPolicy.Kind.GENERAL, policy.kind());
            }
            assertEquals(BopomofoEngine.InputMode.BOPOMOFO, policy.preferredMode());
            assertEquals(3, policy.allowedModes().size());
            assertFalse(policy.isRestricted());
            assertEquals("英/數", policy.modeCaption(BopomofoEngine.InputMode.BOPOMOFO));
            assertTrue(policy.isKeyEnabled("SPACE", BopomofoEngine.InputMode.ENGLISH, false));
            assertTrue(policy.isKeyEnabled("EMOJI", BopomofoEngine.InputMode.BOPOMOFO, false));
            assertTrue(policy.isKeyEnabled("@", BopomofoEngine.InputMode.ENGLISH, false));
        }

        InputFieldPolicy urlWithAsciiHint = InputFieldPolicy.fromValues(
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI,
                EditorInfo.IME_FLAG_FORCE_ASCII);
        assertEquals(InputFieldPolicy.Kind.URL, urlWithAsciiHint.kind());
        assertFalse(urlWithAsciiHint.isRestricted());
    }

    @Test
    public void emailPasswordAndAsciiHintsStartRestrictedButCanUnlock() {
        int[] inputTypes = {
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS,
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD,
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
        };

        for (int inputType : inputTypes) {
            InputFieldPolicy policy = InputFieldPolicy.fromValues(inputType, 0);
            assertEquals(BopomofoEngine.InputMode.ENGLISH, policy.preferredMode());
            assertEquals(2, policy.allowedModes().size());
            assertTrue(policy.isRestricted());
            assertTrue(policy.isKeyEnabled("MODE", BopomofoEngine.InputMode.ENGLISH, false));
            if (policy.kind() == InputFieldPolicy.Kind.EMAIL) {
                assertFalse(policy.isKeyEnabled("SPACE",
                        BopomofoEngine.InputMode.ENGLISH, false));
            } else {
                assertTrue(policy.isKeyEnabled("SPACE",
                        BopomofoEngine.InputMode.ENGLISH, false));
            }
            assertFalse(policy.isKeyEnabled("EMOJI", BopomofoEngine.InputMode.ENGLISH, false));
            assertTrue(policy.isKeyEnabled("@", BopomofoEngine.InputMode.ENGLISH, false));

            InputFieldPolicy unlocked = policy.unrestricted();
            assertFalse(unlocked.isRestricted());
            assertEquals(3, unlocked.allowedModes().size());
            assertTrue(unlocked.isKeyEnabled("SPACE", BopomofoEngine.InputMode.ENGLISH, false));
            assertTrue(unlocked.isKeyEnabled("EMOJI", BopomofoEngine.InputMode.BOPOMOFO, false));
            assertTrue(unlocked.isKeyEnabled("EMOJI", BopomofoEngine.InputMode.NUMBER, false));
        }

        InputFieldPolicy forceAscii = InputFieldPolicy.fromValues(InputType.TYPE_CLASS_TEXT,
                EditorInfo.IME_FLAG_FORCE_ASCII);
        assertEquals(InputFieldPolicy.Kind.ASCII, forceAscii.kind());
        assertTrue(forceAscii.isRestricted());
    }

    @Test
    public void structuredFieldHintsStartNumericButCanUnlock() {
        int[] inputTypes = {
                InputType.TYPE_CLASS_PHONE,
                InputType.TYPE_CLASS_NUMBER,
                InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_SIGNED,
                InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL,
                InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL
                        | InputType.TYPE_NUMBER_FLAG_SIGNED,
                InputType.TYPE_CLASS_DATETIME | InputType.TYPE_DATETIME_VARIATION_DATE,
                InputType.TYPE_CLASS_DATETIME | InputType.TYPE_DATETIME_VARIATION_TIME,
                InputType.TYPE_CLASS_DATETIME | InputType.TYPE_DATETIME_VARIATION_NORMAL
        };

        for (int inputType : inputTypes) {
            InputFieldPolicy policy = InputFieldPolicy.fromValues(inputType, 0);
            assertEquals(BopomofoEngine.InputMode.NUMBER, policy.preferredMode());
            assertEquals(1, policy.allowedModes().size());
            assertTrue(policy.isRestricted());
            assertEquals("ㄅ/英", policy.modeCaption(BopomofoEngine.InputMode.NUMBER));
            assertTrue(policy.isKeyEnabled("MODE", BopomofoEngine.InputMode.NUMBER, false));
            assertFalse(policy.isKeyEnabled("ㄅ", BopomofoEngine.InputMode.BOPOMOFO, false));
            assertFalse(policy.isKeyEnabled("EMOJI", BopomofoEngine.InputMode.NUMBER, false));

            InputFieldPolicy unlocked = policy.unrestricted();
            assertFalse(unlocked.isRestricted());
            assertTrue(unlocked.isKeyEnabled("ㄅ", BopomofoEngine.InputMode.BOPOMOFO, false));
            assertTrue(unlocked.isKeyEnabled("EMOJI", BopomofoEngine.InputMode.BOPOMOFO, false));
            assertTrue(unlocked.isKeyEnabled("SPACE", BopomofoEngine.InputMode.ENGLISH, false));
        }

        InputFieldPolicy unsignedDecimal = InputFieldPolicy.fromValues(
                InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL, 0);
        assertTrue(unsignedDecimal.isKeyEnabled(".",
                BopomofoEngine.InputMode.NUMBER, false));
        assertFalse(unsignedDecimal.isKeyEnabled("-",
                BopomofoEngine.InputMode.NUMBER, false));
        assertFalse(unsignedDecimal.isKeyEnabled("SHIFT",
                BopomofoEngine.InputMode.NUMBER, false));

        InputFieldPolicy signedDecimal = InputFieldPolicy.fromValues(
                InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL
                        | InputType.TYPE_NUMBER_FLAG_SIGNED, 0);
        assertTrue(signedDecimal.isKeyEnabled("-",
                BopomofoEngine.InputMode.NUMBER, false));
    }

    @Test
    public void unlockedPolicyCyclesThroughAllModesWithoutRelocking() {
        BopomofoEngine engine = new BopomofoEngine(CinDictionary.empty());
        InputFieldPolicy email = InputFieldPolicy.fromValues(
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS, 0);
        engine.setAllowedInputModes(email.allowedModes(), email.preferredMode(), true);
        assertEquals(BopomofoEngine.InputMode.ENGLISH, engine.inputMode());

        InputFieldPolicy unlocked = email.unrestricted();
        engine.setAllowedInputModes(unlocked.allowedModes(), unlocked.preferredMode(), false);
        engine.handleSoftKey("MODE");
        assertEquals(BopomofoEngine.InputMode.NUMBER, engine.inputMode());
        engine.handleSoftKey("MODE");
        assertEquals(BopomofoEngine.InputMode.BOPOMOFO, engine.inputMode());
        engine.handleSoftKey("MODE");
        assertEquals(BopomofoEngine.InputMode.ENGLISH, engine.inputMode());
        assertFalse(unlocked.isRestricted());
    }

    @Test
    public void supportedEditorActionsHaveLabelsAndNoEnterActionWins() {
        InputFieldPolicy done = policyWithAction(EditorInfo.IME_ACTION_DONE);
        assertEquals("完成", done.enterLabel());
        assertTrue(done.hasEditorAction());
        assertEquals("下一個", policyWithAction(EditorInfo.IME_ACTION_NEXT).enterLabel());
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
        assertEquals(InputFieldPolicy.Kind.PHONE, InputFieldPolicy.fromValues(
                InputType.TYPE_CLASS_PHONE, 0).kind());
        assertEquals(InputFieldPolicy.Kind.URL, InputFieldPolicy.fromValues(
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI, 0).kind());
        assertEquals(InputFieldPolicy.Kind.INTEGER, InputFieldPolicy.fromValues(
                InputType.TYPE_CLASS_NUMBER, 0).kind());
        assertEquals(InputFieldPolicy.Kind.DATE_TIME, InputFieldPolicy.fromValues(
                InputType.TYPE_CLASS_DATETIME | InputType.TYPE_DATETIME_VARIATION_DATE, 0).kind());
    }

    private InputFieldPolicy policyWithAction(int action) {
        return InputFieldPolicy.fromValues(InputType.TYPE_CLASS_TEXT, action);
    }
}
