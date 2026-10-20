import SwiftUI

/// Tuition invoices: what's due first, then what's paid. Payment happens with the center for now.
struct BillingView: View {
    @Environment(SessionStore.self) private var session
    @State private var invoices = Loader<[Invoice]>()

    var body: some View {
        NavigationStack {
            LoadingView(loader: invoices, retry: load) { list in
                let open = list.filter(\.isOpen)
                let paid = list.filter { !$0.isOpen }
                List {
                    if !open.isEmpty {
                        Section {
                            ForEach(open) { InvoiceRow(invoice: $0) }
                        } header: {
                            Text("Due")
                        } footer: {
                            Text("Total due: \(open.reduce(Decimal(0)) { $0 + $1.amount }.dollars). Questions about a bill? Ask the front desk.")
                        }
                    }
                    if !paid.isEmpty {
                        Section("Paid") {
                            ForEach(paid) { InvoiceRow(invoice: $0) }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .overlay {
                    if list.isEmpty {
                        ContentUnavailableView("No invoices", systemImage: "doc.text",
                                               description: Text("Tuition invoices will show up here."))
                    }
                }
                .refreshable { await load() }
            }
            .navigationTitle("Billing")
        }
        .task { await load() }
    }

    private func load() async {
        await invoices.load(session) { try await $0.invoices() }
    }
}

private struct InvoiceRow: View {
    let invoice: Invoice
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes the amount moves under the month instead of squeezing it.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        layout {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(invoice.periodStart.date.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!).month(.wide))) tuition")
                    .font(.body)
                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(invoice.isPastDue ? .red : .secondary)
            }
            if !typeSize.isAccessibilitySize { Spacer() }
            Text(invoice.amount.dollars)
                .font(.body.weight(invoice.isOpen ? .semibold : .regular))
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var statusLine: String {
        if invoice.isPastDue {
            return "Past due · \(invoice.daysPastDue) \(invoice.daysPastDue == 1 ? "day" : "days") late"
        }
        if invoice.isOpen { return "Due \(invoice.dueOn.mediumLabel)" }
        return "Paid · \(invoice.number)"
    }
}
