#if OFFICIAL_EXTENSIONS
import Combine

enum PeekMarkPDFAction { case purchase, restore, activate }

struct PeekMarkPDFAccessSnapshot: Equatable {
    var hasPro = false
    var price: String?
    var canPurchase = false
    var status: String?
    var isBusy = false
    var isPending = false
}

/// Edition-neutral presentation of the private runtime's verified authority.
@MainActor
final class PeekMarkPDFAccess: ObservableObject {
    static let shared = PeekMarkPDFAccess()
    @Published private(set) var snapshot = PeekMarkPDFAccessSnapshot()

    private var read: (@MainActor () -> PeekMarkPDFAccessSnapshot)?
    private var handler: (@MainActor (PeekMarkPDFAction, String) async -> Void)?

    func install(
        read: @escaping @MainActor () -> PeekMarkPDFAccessSnapshot,
        perform: @escaping @MainActor (PeekMarkPDFAction, String) async -> Void
    ) {
        self.read = read
        handler = perform
        refresh()
    }

    func refresh() {
        let value = read?() ?? PeekMarkPDFAccessSnapshot()
        if value != snapshot { snapshot = value }
    }

    func perform(_ action: PeekMarkPDFAction, key: String = "") async {
        guard let handler else { return }
        await handler(action, key)
        refresh()
    }
}
#endif
