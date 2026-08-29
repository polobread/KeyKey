package tw.chichi77.keykey.android;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class SupporterStateTest {
    private static final long INSTALL_TIME = 1_000_000L;

    @Test
    public void promptIsHiddenBeforeThirtyDays() {
        long now = INSTALL_TIME + SupporterState.TRIAL_DURATION_MILLIS - 1;
        assertFalse(SupporterState.isTrialExpired(INSTALL_TIME, now));
        assertFalse(SupporterState.shouldShowSupportPrompt(INSTALL_TIME, now, false));
    }

    @Test
    public void promptIsShownAfterThirtyDaysWithoutPurchase() {
        long now = INSTALL_TIME + SupporterState.TRIAL_DURATION_MILLIS + 1;
        assertTrue(SupporterState.shouldShowSupportPrompt(INSTALL_TIME, now, false));
    }

    @Test
    public void supporterHidesPromptAfterThirtyDays() {
        long now = INSTALL_TIME + SupporterState.TRIAL_DURATION_MILLIS + 1;
        assertFalse(SupporterState.shouldShowSupportPrompt(INSTALL_TIME, now, true));
    }

    @Test
    public void supporterAlwaysTakesPriorityOverTrialExpiry() {
        assertFalse(SupporterState.shouldShowSupportPrompt(
                INSTALL_TIME, Long.MAX_VALUE, true));
    }

    @Test
    public void cachedSupporterCanHideImePromptWithoutBillingClient() {
        long now = INSTALL_TIME + SupporterState.TRIAL_DURATION_MILLIS;
        assertFalse(SupporterState.shouldShowSupportPrompt(INSTALL_TIME, now, true));
    }

    @Test
    public void trialExpiresAtExactThirtyDayBoundary() {
        long now = INSTALL_TIME + SupporterState.TRIAL_DURATION_MILLIS;
        assertTrue(SupporterState.isTrialExpired(INSTALL_TIME, now));
        assertTrue(SupporterState.shouldShowSupportPrompt(INSTALL_TIME, now, false));
    }
}
