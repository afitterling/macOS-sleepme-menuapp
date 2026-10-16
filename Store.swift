// StoreKit 2 gating for Lunair Pro — a single non-consumable unlock.
//
// The source of truth for the unlock is StoreKit's current entitlements. We
// also mirror the flag into the iCloud key-value store so the unlocked state
// follows the user across their Macs and is available before StoreKit finishes
// loading. For local development, attach the Products.storekit configuration to
// the run scheme so purchases work without App Store Connect.

import AppKit
import StoreKit

@MainActor
final class Store {
    static let shared = Store()
    static let proProductID = "tech.sp33c.sleeptimer.pro"

    private(set) var proProduct: Product?
    private(set) var isPro = false

    /// Invoked on the main actor whenever the product or entitlement changes,
    /// so the menu and paywall can refresh.
    var onChange: (() -> Void)?

    private var updatesTask: Task<Void, Never>?
    private let cloud = NSUbiquitousKeyValueStore.default

    private init() {
        // Optimistically restore the unlock from iCloud so the UI is correct
        // before StoreKit's async load completes.
        isPro = cloud.bool(forKey: Self.proProductID)
        cloud.synchronize()

        // Pick up purchases, restores, and revocations that happen out of band.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }

        Task {
            await loadProduct()
            await refreshEntitlement()
        }
    }

    var priceText: String { proProduct?.displayPrice ?? "—" }

    func loadProduct() async {
        do {
            proProduct = try await Product.products(for: [Self.proProductID]).first
            onChange?()
        } catch {
            NSLog("Lunair: failed to load products — \(error)")
        }
    }

    func refreshEntitlement() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let txn) = result,
               txn.productID == Self.proProductID,
               txn.revocationDate == nil {
                owned = true
            }
        }
        setPro(owned)
    }

    @discardableResult
    func purchase() async -> Bool {
        guard let product = proProduct else { return false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let txn) = verification {
                    await txn.finish()
                    setPro(true)
                    return true
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            NSLog("Lunair: purchase failed — \(error)")
        }
        return false
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        if case .verified(let txn) = result {
            await txn.finish()
            await refreshEntitlement()
        }
    }

    private func setPro(_ value: Bool) {
        guard value != isPro else { return }
        isPro = value
        cloud.set(value, forKey: Self.proProductID)
        cloud.synchronize()
        onChange?()
    }
}
