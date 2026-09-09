import KeyKeyEngine
import OSLog
import StoreKit

@MainActor
protocol SupporterStoreClient {
    func loadPrice() async throws -> String?
    func purchase() async throws -> SupporterPurchaseResult
    func sync() async throws
    func hasEntitlement() async -> Bool
}

enum SupporterPurchaseResult {
    case verified(finish: @MainActor () async -> Void)
    case unverified, pending, cancelled
}

@MainActor
private final class StoreKitSupporterClient: SupporterStoreClient {
    private var product: Product?

    func loadPrice() async throws -> String? {
        product = nil
        product = try await Product.products(for: [SupporterState.productIdentifier]).first
        return product?.displayPrice
    }

    func purchase() async throws -> SupporterPurchaseResult {
        guard let product else { return .unverified }
        switch try await product.purchase() {
        case .success(let result):
            guard case .verified(let transaction) = result,
                  transaction.productID == SupporterState.productIdentifier,
                  transaction.revocationDate == nil
            else { return .unverified }
            return .verified(finish: { await transaction.finish() })
        case .pending: return .pending
        case .userCancelled: return .cancelled
        @unknown default: return .unverified
        }
    }

    func sync() async throws { try await AppStore.sync() }

    func hasEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == SupporterState.productIdentifier,
                  transaction.revocationDate == nil
            else { continue }
            return true
        }
        return false
    }
}

@MainActor
final class SupporterStore {
    enum Operation: Equatable {
        case idle, loading, purchasing, restoring
    }

    struct ViewState: Equatable {
        var operation: Operation = .idle
        var isBusy: Bool { operation != .idle }
        var supporter = false
        var formattedPrice: String?
        var productAvailable = false
    }

    var onStateChanged: ((ViewState) -> Void)?
    var onError: ((String) -> Void)?

    private(set) var state: ViewState {
        didSet { onStateChanged?(state) }
    }

    private let supporterState: SupporterState
    private let client: any SupporterStoreClient
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.github.polobread.inputmethod.chichi77.ios",
        category: "StoreKit"
    )
    private var transactionUpdates: Task<Void, Never>?
    private var started = false

    init(
        supporterState: SupporterState = SupporterState(),
        client: (any SupporterStoreClient)? = nil
    ) {
        self.supporterState = supporterState
        self.client = client ?? StoreKitSupporterClient()
        supporterState.recordFirstUse()
        state = ViewState(supporter: supporterState.isSupporter)
    }

    deinit {
        transactionUpdates?.cancel()
    }

    func start() {
        guard !started else { return }
        started = true
        onStateChanged?(state)
        transactionUpdates = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                await self?.handleTransaction(result)
            }
        }
        Task { [weak self] in await self?.reload() }
    }

    func purchase() async {
        guard !state.isBusy, !state.supporter else { return }
        guard state.productAvailable else {
            onError?("尚未取得 App Store 商品資訊，請重新載入價格後再試。")
            return
        }
        state.operation = .purchasing
        defer { state.operation = .idle }
        do {
            switch try await client.purchase() {
            case .verified(let finish):
                supporterState.setSupporter(true)
                state.supporter = true
                await finish()
            case .unverified:
                onError?("無法驗證這筆購買，請稍後再試。")
            case .pending:
                onError?("這筆購買正在等待核准，完成後會自動更新。")
            case .cancelled:
                break
            }
        } catch is CancellationError {
            // Cancelling the task must release the controls without an error alert.
        } catch {
            logger.error("Supporter purchase failed: \(String(describing: error), privacy: .public)")
            onError?("目前無法完成購買，請稍後再試。")
        }
    }

    func restore() async {
        guard !state.isBusy else { return }
        state.operation = .restoring
        defer { state.operation = .idle }
        do {
            try await client.sync()
            await refreshEntitlement()
            if !state.supporter {
                onError?("此 Apple 帳號目前沒有可恢復的支持購買。")
            }
        } catch is CancellationError {
            // The user may retry after cancellation.
        } catch {
            logger.error("Supporter restore failed: \(String(describing: error), privacy: .public)")
            onError?("目前無法恢復購買，請稍後再試。")
        }
    }

    func reload(showError: Bool = false) async {
        guard !state.isBusy else { return }
        state.operation = .loading
        defer { state.operation = .idle }
        await refreshEntitlement()
        do {
            state.formattedPrice = nil
            state.productAvailable = false
            state.formattedPrice = try await client.loadPrice()
            state.productAvailable = state.formattedPrice != nil
            if !state.productAvailable {
                logger.error("Supporter product was not returned by App Store")
                if showError {
                    onError?("App Store 目前沒有回傳商品資訊，請稍後再試。")
                }
            }
        } catch is CancellationError {
            // A cancelled load leaves the retry action available.
        } catch {
            state.formattedPrice = nil
            state.productAvailable = false
            logger.error("Supporter product load failed: \(String(describing: error), privacy: .public)")
            if showError {
                onError?("目前無法載入 App Store 商品資訊，請稍後再試。")
            }
        }
    }

    private func refreshEntitlement() async {
        let entitled = await client.hasEntitlement()
        supporterState.setSupporter(entitled)
        state.supporter = entitled
    }

    private func handleTransaction(_ result: VerificationResult<Transaction>) async {
        guard let transaction = verified(result),
              transaction.productID == SupporterState.productIdentifier
        else { return }
        supporterState.setSupporter(transaction.revocationDate == nil)
        state.supporter = transaction.revocationDate == nil
        await transaction.finish()
    }

    private func verified<T>(_ result: VerificationResult<T>) -> T? {
        guard case .verified(let value) = result else { return nil }
        return value
    }
}
