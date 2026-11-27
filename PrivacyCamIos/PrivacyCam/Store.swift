import StoreKit
import SwiftUI

/// 한 번 결제로 여는 Pro. 영수증은 StoreKit 2 가 기기 안에서 검증한다.
@MainActor @Observable
final class Store {
    static let proID = "com.wonkwh.privacycam.pro"
    private(set) var isPro = false

    /// 현재 권한을 읽은 뒤 구매·환불·가족 공유 변경을 계속 반영한다.
    func observe() async {
        await refresh()
        for await result in Transaction.updates {
            if case .verified(let transaction) = result { await transaction.finish() }
            await refresh()
        }
    }

    /// 환불되지 않은 Pro 거래가 있는지 다시 확인한다.
    func refresh() async {
        var pro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.proID, t.revocationDate == nil { pro = true }
        }
        isPro = pro
    }
}

struct ProPaywall: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var restoreFailed = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("여러 장을 한 번에")
                    .font(.title.weight(.heavy))
                VStack(alignment: .leading, spacing: 12) {
                    Label("최대 10장을 고르면 차례로 검사하고 한꺼번에 저장", systemImage: "square.stack")
                    Label("한 번 결제로 계속 사용, 가족 공유 가능", systemImage: "infinity")
                    Label("한 장씩 가리기와 메타데이터 제거는 계속 무료", systemImage: "checkmark.shield")
                }
                .font(.subheadline)
                Spacer(minLength: 0)
                ProductView(id: Store.proID)
                    .productViewStyle(.compact)
                    .padding(14)
                    .background(Theme.fill, in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
                Button("구매 복원") {
                    Task {
                        do { try await AppStore.sync() } catch { restoreFailed = true }
                        await store.refresh()
                    }
                }
                .font(.footnote)
                .frame(maxWidth: .infinity)
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Theme.background)
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success(.verified(let transaction))) = result { await transaction.finish() }
            await store.refresh()
        }
        .onChange(of: store.isPro) { _, pro in if pro { dismiss() } }
        .alert("복원하지 못했습니다", isPresented: $restoreFailed) { Button("확인") {} }
    }
}
