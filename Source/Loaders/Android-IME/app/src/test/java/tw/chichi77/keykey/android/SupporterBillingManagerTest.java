package tw.chichi77.keykey.android;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import com.android.billingclient.api.Purchase;

import org.junit.Test;

public final class SupporterBillingManagerTest {
    @Test
    public void pendingPurchaseDoesNotGrantEntitlement() {
        assertFalse(SupporterBillingManager.grantsEntitlement(
                Purchase.PurchaseState.PENDING));
    }

    @Test
    public void purchasedStateGrantsEntitlement() {
        assertTrue(SupporterBillingManager.grantsEntitlement(
                Purchase.PurchaseState.PURCHASED));
    }
}
