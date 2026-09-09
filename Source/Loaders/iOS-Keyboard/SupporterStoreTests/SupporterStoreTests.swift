import Foundation
import KeyKeyEngine
import Testing
@testable import SupporterStoreFlow

@MainActor
private final class FakeClient: SupporterStoreClient {
    enum Failure: Error { case offline }
    var price: String? = "NT$90.00"
    var entitled = false
    var result: SupporterPurchaseResult = .cancelled
    var failure: Error?
    var pause: (() async -> Void)?
    var loads = 0
    var purchases = 0
    var restores = 0

    private func perform() async throws {
        await pause?()
        try Task.checkCancellation()
        if let failure { throw failure }
    }

    func loadPrice() async throws -> String? {
        loads += 1
        try await perform()
        return price
    }

    func purchase() async throws -> SupporterPurchaseResult {
        purchases += 1
        try await perform()
        return result
    }

    func sync() async throws {
        restores += 1
        try await perform()
    }

    func hasEntitlement() async -> Bool { entitled }
}

// A deterministic suspension point; no sleeps or network timing assumptions.
@MainActor
private final class Gate {
    private var entered = false
    private var observer: CheckedContinuation<Void, Never>?
    private var blocked: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation { continuation in
            blocked = continuation
            entered = true
            observer?.resume()
            observer = nil
        }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { observer = $0 }
    }

    func open() {
        blocked?.resume()
        blocked = nil
    }
}

@MainActor
private final class Fixture {
    let suite = "SupporterStoreTests.\(UUID().uuidString)"
    let cache: SupporterState
    let client = FakeClient()
    let store: SupporterStore
    var messages: [String] = []
    var operations: [SupporterStore.Operation] = []

    init() {
        cache = SupporterState(defaults: UserDefaults(suiteName: suite)!)
        store = SupporterStore(supporterState: cache, client: client)
        store.onError = { [weak self] in self?.messages.append($0) }
        store.onStateChanged = { [weak self] in self?.operations.append($0.operation) }
    }

    func cleanUp() { UserDefaults().removePersistentDomain(forName: suite) }

    func run(_ operation: SupporterStore.Operation) async {
        switch operation {
        case .loading: await store.reload(showError: true)
        case .purchasing: await store.purchase()
        case .restoring: await store.restore()
        case .idle: Issue.record("Idle is not an action")
        }
    }
}

@Suite @MainActor
struct SupporterStoreTests {
    @Test(arguments: [false, true])
    func unavailableProductCanBeRetried(throwsError: Bool) async {
        let f = Fixture()
        defer { f.cleanUp() }
        f.client.price = nil
        f.client.failure = throwsError ? FakeClient.Failure.offline : nil
        await f.store.reload(showError: true)
        #expect(!f.store.state.productAvailable)
        #expect(f.store.state.formattedPrice == nil)
        #expect(!f.store.state.isBusy)
        #expect(f.messages.count == 1)
        await f.store.purchase()
        #expect(f.client.purchases == 0)

        f.client.failure = nil
        f.client.price = "NT$90.00"
        await f.store.reload(showError: true)
        #expect(f.store.state.productAvailable)
        #expect(f.store.state.formattedPrice == "NT$90.00")
        await f.store.purchase()
        #expect(f.client.purchases == 1)
        #expect(!f.store.state.isBusy)
    }

    @Test(arguments: [SupporterStore.Operation.loading, .purchasing, .restoring])
    func inFlightOperationRejectsAllOtherActions(operation: SupporterStore.Operation) async {
        let f = Fixture()
        defer { f.cleanUp() }
        await f.store.reload()
        let gate = Gate()
        f.client.pause = { await gate.suspend() }
        let task = Task { await f.run(operation) }
        await gate.waitUntilEntered()
        #expect(f.store.state.operation == operation)
        #expect(f.store.state.isBusy)
        let counts = [f.client.loads, f.client.purchases, f.client.restores]
        await f.store.purchase()
        await f.store.restore()
        await f.store.reload(showError: true)
        #expect([f.client.loads, f.client.purchases, f.client.restores] == counts)
        #expect(f.messages.isEmpty)
        gate.open()
        await task.value
        #expect(f.store.state.operation == .idle)
        #expect(f.operations.contains(operation))
        #expect(f.operations.last == .idle)
        f.client.pause = nil
        await f.store.reload()
        #expect(f.client.loads == counts[0] + 1)
    }

    @Test(arguments: [SupporterStore.Operation.loading, .purchasing, .restoring])
    func cancellationReleasesControls(operation: SupporterStore.Operation) async {
        let f = Fixture()
        defer { f.cleanUp() }
        await f.store.reload()
        let gate = Gate()
        f.client.pause = { await gate.suspend() }
        let task = Task { await f.run(operation) }
        await gate.waitUntilEntered()
        task.cancel()
        gate.open()
        await task.value
        #expect(!f.store.state.isBusy)
        #expect(f.messages.isEmpty)
        #expect(!f.cache.isSupporter)
        f.client.pause = nil
        await f.store.reload()
        #expect(f.store.state.productAvailable)
    }

    @Test(arguments: [SupporterStore.Operation.loading, .purchasing, .restoring])
    func errorsReleaseControlsAndAllowRetry(operation: SupporterStore.Operation) async {
        let f = Fixture()
        defer { f.cleanUp() }
        await f.store.reload()
        f.client.failure = FakeClient.Failure.offline
        await f.run(operation)
        #expect(!f.store.state.isBusy)
        #expect(f.messages.count == 1)
        #expect(!f.cache.isSupporter)
        if operation == .loading {
            #expect(!f.store.state.productAvailable)
            #expect(f.store.state.formattedPrice == nil)
        }
        f.client.failure = nil
        f.client.entitled = operation == .restoring
        await f.run(operation)
        #expect(!f.store.state.isBusy)
        #expect(f.messages.count == 1)
    }

    @Test
    func successfulPurchaseCachesBeforeFinishingAndPreventsRepurchase() async {
        let f = Fixture()
        defer { f.cleanUp() }
        await f.store.reload()
        var finished = false
        f.client.result = .verified(finish: {
            #expect(f.cache.isSupporter)
            #expect(f.store.state.supporter)
            #expect(f.store.state.operation == .purchasing)
            finished = true
        })
        await f.store.purchase()
        #expect(finished)
        #expect(!f.store.state.isBusy)
        #expect(f.messages.isEmpty)
        await f.store.purchase()
        #expect(f.client.purchases == 1)
    }

    @Test
    func cancelledPendingAndUnverifiedPurchasesDoNotGrantSupport() async {
        let f = Fixture()
        defer { f.cleanUp() }
        await f.store.reload()
        for result in [SupporterPurchaseResult.cancelled, .pending, .unverified] {
            f.client.result = result
            await f.store.purchase()
            #expect(!f.store.state.isBusy)
            #expect(!f.cache.isSupporter)
            #expect(!f.store.state.supporter)
        }
        #expect(f.client.purchases == 3)
        #expect(f.messages.count == 2)
    }

    @Test(arguments: [false, true])
    func restoreUpdatesSharedCacheWithoutAProduct(entitled: Bool) async {
        let f = Fixture()
        defer { f.cleanUp() }
        f.client.entitled = entitled
        await f.store.restore()
        #expect(f.cache.isSupporter == entitled)
        #expect(f.store.state.supporter == entitled)
        #expect(!f.store.state.isBusy)
        #expect(f.messages.count == (entitled ? 0 : 1))
        #expect(f.client.loads == 0)
    }
}
