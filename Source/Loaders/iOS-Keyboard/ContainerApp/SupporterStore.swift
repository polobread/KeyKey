import KeyKeyEngine
import StoreKit

@MainActor
final class SupporterStore {
    struct ViewState: Equatable {
        var checking = true
        var supporter = false
        var formattedPrice: String?
    }

    var onStateChanged: ((ViewState) -> Void)?
    var onError: ((String) -> Void)?

    private(set) var state: ViewState {
        didSet { onStateChanged?(state) }
    }

    private let supporterState: SupporterState
    private var product: Product?
    private var transactionUpdates: Task<Void, Never>?
    private var started = false

    init(supporterState: SupporterState = SupporterState()) {
        self.supporterState = supporterState
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
        guard let product else {
            onError?("目前無法連線 App Store 結帳服務，請稍後再試。")
            return
        }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard let transaction = verified(result),
                      transaction.productID == SupporterState.productIdentifier
                else {
                    onError?("無法驗證這筆購買，請稍後再試。")
                    return
                }
                supporterState.setSupporter(true)
                state.supporter = true
                await transaction.finish()
            case .pending:
                onError?("這筆購買正在等待核准，完成後會自動更新。")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            onError?("目前無法完成購買，請稍後再試。")
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !state.supporter {
                onError?("此 Apple 帳號目前沒有可恢復的支持購買。")
            }
        } catch {
            onError?("目前無法恢復購買，請稍後再試。")
        }
    }

    private func reload() async {
        await refreshEntitlement()
        do {
            product = try await Product.products(
                for: [SupporterState.productIdentifier]
            ).first
            state.formattedPrice = product?.displayPrice
        } catch {
            product = nil
            state.formattedPrice = nil
        }
        state.checking = false
    }

    private func refreshEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = verified(result),
                  transaction.productID == SupporterState.productIdentifier,
                  transaction.revocationDate == nil
            else { continue }
            entitled = true
            break
        }
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
