package tw.chichi77.keykey.android;

import android.app.Activity;
import android.content.Context;

import com.android.billingclient.api.AcknowledgePurchaseParams;
import com.android.billingclient.api.BillingClient;
import com.android.billingclient.api.BillingClientStateListener;
import com.android.billingclient.api.BillingFlowParams;
import com.android.billingclient.api.BillingResult;
import com.android.billingclient.api.PendingPurchasesParams;
import com.android.billingclient.api.ProductDetails;
import com.android.billingclient.api.Purchase;
import com.android.billingclient.api.PurchasesUpdatedListener;
import com.android.billingclient.api.QueryProductDetailsParams;
import com.android.billingclient.api.QueryProductDetailsResult;
import com.android.billingclient.api.QueryPurchasesParams;

import java.util.List;

final class SupporterBillingManager implements PurchasesUpdatedListener {
    static final String PRODUCT_ID = "chichi_supporter";
    static final String PURCHASE_OPTION_ID = "buy";

    interface Listener {
        void onStateChanged(boolean billingQueryComplete, boolean supporter,
                            String formattedPrice);
        void onPurchaseError();
    }

    private final Context context;
    private final Listener listener;
    private final BillingClient billingClient;
    private ProductDetails productDetails;
    private ProductDetails.OneTimePurchaseOfferDetails purchaseOffer;
    private String formattedPrice;
    private boolean productQueryComplete;
    private boolean purchaseQueryComplete;

    SupporterBillingManager(Context context, Listener listener) {
        this.context = context.getApplicationContext();
        this.listener = listener;
        billingClient = BillingClient.newBuilder(this.context)
                .setListener(this)
                .enablePendingPurchases(PendingPurchasesParams.newBuilder()
                        .enableOneTimeProducts()
                        .build())
                .enableAutoServiceReconnection()
                .build();
    }

    void start() {
        notifyStateChanged();
        billingClient.startConnection(new BillingClientStateListener() {
            @Override
            public void onBillingSetupFinished(BillingResult billingResult) {
                if (billingResult.getResponseCode() != BillingClient.BillingResponseCode.OK) {
                    productQueryComplete = true;
                    purchaseQueryComplete = true;
                    notifyStateChanged();
                    return;
                }
                queryProductDetails();
                queryPurchases();
            }

            @Override
            public void onBillingServiceDisconnected() {
                // Auto-reconnection handles the next Billing API request. IME behavior is local.
            }
        });
    }

    void launchPurchase(Activity activity) {
        if (productDetails == null || purchaseOffer == null || !billingClient.isReady()) {
            listener.onPurchaseError();
            return;
        }
        BillingFlowParams.ProductDetailsParams productParams =
                BillingFlowParams.ProductDetailsParams.newBuilder()
                        .setProductDetails(productDetails)
                        .setOfferToken(purchaseOffer.getOfferToken())
                        .build();
        BillingFlowParams flowParams = BillingFlowParams.newBuilder()
                .setProductDetailsParamsList(List.of(productParams))
                .build();
        BillingResult result = billingClient.launchBillingFlow(activity, flowParams);
        int responseCode = result.getResponseCode();
        if (responseCode != BillingClient.BillingResponseCode.OK
                && responseCode != BillingClient.BillingResponseCode.USER_CANCELED) {
            listener.onPurchaseError();
        }
    }

    void close() {
        billingClient.endConnection();
    }

    @Override
    public void onPurchasesUpdated(BillingResult billingResult, List<Purchase> purchases) {
        int responseCode = billingResult.getResponseCode();
        if (responseCode == BillingClient.BillingResponseCode.USER_CANCELED) return;
        if (responseCode != BillingClient.BillingResponseCode.OK || purchases == null) {
            listener.onPurchaseError();
            return;
        }
        for (Purchase purchase : purchases) processPurchase(purchase);
    }

    static boolean grantsEntitlement(int purchaseState) {
        return purchaseState == Purchase.PurchaseState.PURCHASED;
    }

    private void queryProductDetails() {
        QueryProductDetailsParams.Product product = QueryProductDetailsParams.Product.newBuilder()
                .setProductId(PRODUCT_ID)
                .setProductType(BillingClient.ProductType.INAPP)
                .build();
        QueryProductDetailsParams params = QueryProductDetailsParams.newBuilder()
                .setProductList(List.of(product))
                .build();
        billingClient.queryProductDetailsAsync(params, this::onProductDetailsResponse);
    }

    private void onProductDetailsResponse(BillingResult billingResult,
                                          QueryProductDetailsResult result) {
        if (billingResult.getResponseCode() == BillingClient.BillingResponseCode.OK) {
            for (ProductDetails details : result.getProductDetailsList()) {
                if (!PRODUCT_ID.equals(details.getProductId())) continue;
                ProductDetails.OneTimePurchaseOfferDetails offer = findBuyOffer(details);
                if (offer != null) {
                    productDetails = details;
                    purchaseOffer = offer;
                    formattedPrice = offer.getFormattedPrice();
                    break;
                }
            }
        }
        productQueryComplete = true;
        notifyStateChanged();
    }

    private ProductDetails.OneTimePurchaseOfferDetails findBuyOffer(ProductDetails details) {
        List<ProductDetails.OneTimePurchaseOfferDetails> offers =
                details.getOneTimePurchaseOfferDetailsList();
        if (offers != null) {
            for (ProductDetails.OneTimePurchaseOfferDetails offer : offers) {
                if (PURCHASE_OPTION_ID.equals(offer.getPurchaseOptionId())) return offer;
            }
        }
        ProductDetails.OneTimePurchaseOfferDetails offer =
                details.getOneTimePurchaseOfferDetails();
        return offer != null && PURCHASE_OPTION_ID.equals(offer.getPurchaseOptionId())
                ? offer : null;
    }

    private void queryPurchases() {
        QueryPurchasesParams params = QueryPurchasesParams.newBuilder()
                .setProductType(BillingClient.ProductType.INAPP)
                .build();
        billingClient.queryPurchasesAsync(params, (billingResult, purchases) -> {
            if (billingResult.getResponseCode() == BillingClient.BillingResponseCode.OK) {
                boolean supporter = false;
                for (Purchase purchase : purchases) {
                    if (!isSupporterProduct(purchase) || !grantsEntitlement(
                            purchase.getPurchaseState())) continue;
                    supporter = true;
                    acknowledgeIfNeeded(purchase);
                }
                SupporterState.setSupporter(context, supporter);
            }
            purchaseQueryComplete = true;
            notifyStateChanged();
        });
    }

    private void processPurchase(Purchase purchase) {
        if (!isSupporterProduct(purchase)
                || !grantsEntitlement(purchase.getPurchaseState())) return;
        SupporterState.setSupporter(context, true);
        notifyStateChanged();
        acknowledgeIfNeeded(purchase);
    }

    private boolean isSupporterProduct(Purchase purchase) {
        return purchase.getProducts().contains(PRODUCT_ID);
    }

    private void acknowledgeIfNeeded(Purchase purchase) {
        if (purchase.isAcknowledged()) return;
        AcknowledgePurchaseParams params = AcknowledgePurchaseParams.newBuilder()
                .setPurchaseToken(purchase.getPurchaseToken())
                .build();
        billingClient.acknowledgePurchase(params, billingResult -> {
            // Entitlement is granted for PURCHASED immediately; acknowledgment is never consumed.
        });
    }

    private void notifyStateChanged() {
        listener.onStateChanged(productQueryComplete && purchaseQueryComplete,
                SupporterState.isSupporter(context), formattedPrice);
    }
}
