//
//  MainTabView.swift
//  alpha
//
//  Created by Claude Code on 11/25/25.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    @State private var selectedMoneySection: MoneySection = .invoices
    @State private var showingQuickActions = false
    @State private var showingQuickEntry = false
    @State private var showingCreateInvoice = false
    @State private var showingQuickBill = false
    @State private var showingQuickPayment = false
    @State private var showingCreateProject = false
    @State private var showingAddExpense = false
    @State private var showingTaxPrep = false

    init() {
        // Configure tab bar appearance
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }

    // Use the account-type-aware visible tabs from AppState
    var visibleTabs: [MainTab] {
        appState.visibleTabs
    }

    var body: some View {
        ZStack {
            // Dynamic Tab View based on capabilities
            TabView(selection: $selectedTab) {
                ForEach(visibleTabs) { tab in
                    tabContent(for: tab)
                        .tabItem {
                            Label(tab.title, systemImage: tab.icon)
                        }
                        .tag(tab.rawValue)
                }
            }
            .tint(Color(uiColor: .label))

            // Context-aware Floating Action Button
            if let currentTab = visibleTabs.first(where: { $0.rawValue == selectedTab }),
               currentTab != .more {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()

                        switch currentTab {
                        case .dashboard, .money:
                            // Show FAB that opens Quick Actions sheet
                            if hasAnyQuickAction {
                                Button(action: { showingQuickActions = true }) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(Color(uiColor: .systemBackground))
                                        .frame(width: 60, height: 60)
                                        .background(
                                            Circle()
                                                .fill(Color(uiColor: .label))
                                                .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
                                        )
                                }
                                .accessibilityLabel("Quick Actions")
                            }

                        case .timeEntries:
                            if appState.hasCapability(.trackTime) {
                                Button(action: { showingQuickEntry = true }) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(Color(uiColor: .systemBackground))
                                        .frame(width: 60, height: 60)
                                        .background(
                                            Circle()
                                                .fill(Color(uiColor: .label))
                                                .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
                                        )
                                }
                                .accessibilityLabel("Log Time")
                            }

                        case .projects:
                            if appState.hasCapability(.createProjects) {
                                Button(action: { showingCreateProject = true }) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(Color(uiColor: .systemBackground))
                                        .frame(width: 60, height: 60)
                                        .background(
                                            Circle()
                                                .fill(Color(uiColor: .label))
                                                .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
                                        )
                                }
                                .accessibilityLabel("Create project")
                            }

                        case .more:
                            EmptyView()
                        }

                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 70)
                }
            }
        }
        .sheet(isPresented: $showingQuickActions) {
            QuickActionsSheet(isPresented: $showingQuickActions, actions: quickActions)
                .withAppTheme()
        }
        .sheet(isPresented: $showingQuickEntry) {
            QuickEntrySheet(isPresented: $showingQuickEntry)
                .withAppTheme()
        }
        .sheet(isPresented: $showingCreateInvoice) {
            CreateInvoiceSheet(isPresented: $showingCreateInvoice)
                .withAppTheme()
        }
        .sheet(isPresented: $showingQuickBill) {
            QuickBillSheet(isPresented: $showingQuickBill)
                .withAppTheme()
        }
        .sheet(isPresented: $showingQuickPayment) {
            QuickPaymentSheet(isPresented: $showingQuickPayment)
                .withAppTheme()
        }
        .sheet(isPresented: $showingCreateProject) {
            ProjectFormSheet(isPresented: $showingCreateProject, onSave: {})
                .withAppTheme()
        }
        .sheet(isPresented: $showingTaxPrep) { NavigationStack { WorkspaceReportView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingTaxPrep = false } } } } }
        .sheet(isPresented: $showingAddExpense) {
            ExpenseFormSheet(isPresented: $showingAddExpense, onSave: {})
                .withAppTheme()
        }
    }

    // MARK: - Helper Methods

    @ViewBuilder
    private func tabContent(for tab: MainTab) -> some View {
        switch tab {
        case .dashboard:
            HomeView { destination in
                openFinancialSearchDestination(destination)
            }
        case .timeEntries:
            TasksView()
        case .money:
            MoneyView(selectedSection: $selectedMoneySection)
        case .projects:
            ProjectsListView()
        case .more:
            MoreView()
        }
    }

    private func openFinancialSearchDestination(_ destination: FinancialSearchDestination) {
        switch destination {
        case .invoices:
            selectedMoneySection = .invoices
            selectedTab = MainTab.money.rawValue
        case .bills:
            selectedMoneySection = .bills
            selectedTab = MainTab.money.rawValue
        case .expenses:
            selectedMoneySection = .expenses
            selectedTab = MainTab.money.rawValue
        case .timeEntries:
            selectedTab = MainTab.timeEntries.rawValue
        case .projects:
            selectedTab = MainTab.projects.rawValue
        case .taxPrep:
            showingTaxPrep = true
        }
    }

    // Quick Actions for the Home tab sheet
    private var quickActions: [QuickAction] {
        var actions: [QuickAction] = []

        if appState.currentUser?.accountType != .business && appState.hasCapability(.trackTime) {
            actions.append(QuickAction(
                icon: "clock.fill",
                label: "Log Time",
                color: .purple,
                action: { showingQuickEntry = true }
            ))
        }

        if appState.hasCapability(.createInvoices) {
            actions.append(QuickAction(
                icon: "doc.badge.plus",
                label: "Create Invoice",
                color: .blue,
                action: { showingCreateInvoice = true }
            ))
        }

        if appState.hasCapability(.viewBills) || appState.hasCapability(.viewAccountsPayable) || appState.hasCapability(.manageBills) {
            actions.append(QuickAction(
                icon: "creditcard.fill",
                label: "New Bill",
                color: .indigo,
                action: { showingQuickBill = true }
            ))
        }

        if appState.hasCapability(.submitExpenses) {
            actions.append(QuickAction(
                icon: "dollarsign.circle.fill",
                label: "Add Expense",
                color: .green,
                action: { showingAddExpense = true }
            ))
        }

        if appState.hasCapability(.recordPayments) {
            actions.append(QuickAction(
                icon: "creditcard.fill",
                label: "Record Payment",
                color: .orange,
                action: { showingQuickPayment = true }
            ))
        }

        return actions
    }

    private var hasAnyQuickAction: Bool {
        (appState.currentUser?.accountType != .business && appState.hasCapability(.trackTime)) ||
        appState.hasCapability(.createInvoices) ||
        appState.hasCapability(.viewBills) ||
        appState.hasCapability(.viewAccountsPayable) ||
        appState.hasCapability(.manageBills) ||
        appState.hasCapability(.submitExpenses) ||
        appState.hasCapability(.recordPayments)
    }
}

private enum MoneySection: String, CaseIterable, Identifiable {
    case invoices = "Invoices"
    case bills = "Bills"
    case expenses = "Expenses"

    var id: String { rawValue }
}

private struct MoneyView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedSection: MoneySection

    private var visibleSections: [MoneySection] {
        var sections: [MoneySection] = []

        if appState.hasCapability(.viewInvoices) || appState.hasCapability(.viewAccountsReceivable) {
            sections.append(.invoices)
        }

        if appState.hasCapability(.viewBills) || appState.hasCapability(.viewAccountsPayable) || appState.hasCapability(.manageBills) {
            sections.append(.bills)
        }

        if appState.hasCapability(.viewOwnExpenses) || appState.hasCapability(.viewTeamExpenses) || appState.hasCapability(.submitExpenses) {
            sections.append(.expenses)
        }

        return sections.isEmpty ? [.expenses] : sections
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Money Section", selection: $selectedSection) {
                    ForEach(visibleSections) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                Group {
                    switch selectedSection {
                    case .invoices:
                        BillingView(showSectionPicker: false, embeddedInParentNavigation: true)
                    case .bills:
                        if appState.hasCapability(.viewAccountsPayable) { VendorBillsView() } else { BillsView() }
                    case .expenses:
                        ExpenseViewContent()
                    }
                }
            }
            .navigationTitle("Money")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !visibleSections.contains(selectedSection),
                   let first = visibleSections.first {
                    selectedSection = first
                }
            }
        }
    }
}

private struct MoreView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingAccount = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingAccount = true
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.alphaPrimary)
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Text(appState.currentUser?.initials ?? "")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(appState.currentUser?.name ?? "Account")
                                    .foregroundColor(.alphaPrimaryText)
                                Text(appState.currentUser?.email ?? "")
                                    .font(.alphaBodySmall)
                                    .foregroundColor(.alphaSecondaryText)
                            }
                        }
                    }
                }

                Section("Core") {
                    NavigationLink("Review Inbox", destination: ReviewInboxView())
                    if appState.hasCapability(.viewClients) {
                        NavigationLink(destination: ContactsListView()) {
                            Label("Clients", systemImage: "person.2.fill")
                        }
                    }

                    if appState.hasCapability(.viewTaxDashboard) {
                        NavigationLink(destination: TaxComplianceView()) {
                            Label("Tax Prep", systemImage: "calculator.fill")
                        }
                    }

                    NavigationLink(destination: SettingsView()) {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                }

                if ProductScope.showAdvancedModules {
                    Section("Advanced") {
                        if appState.currentUser?.canAccessAccounting == true {
                            Label("Accounting", systemImage: "book.closed.fill")
                        }
                        if appState.currentUser?.canAccessPayroll == true {
                            Label("Payroll", systemImage: "banknote.fill")
                        }
                        if appState.currentUser?.canAccessInventory == true {
                            Label("Inventory", systemImage: "shippingbox.fill")
                        }
                        if appState.currentUser?.canManageTeam == true {
                            NavigationLink(destination: TeamView()) {
                                Label("Team", systemImage: "person.3.fill")
                            }
                        }
                    }
                }
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingAccount) {
                AccountSheet(isPresented: $showingAccount)
                    .withAppTheme()
            }
        }
    }
}

// MARK: - Preview

#Preview("Main Tab View") {
    MainTabView()
        .environmentObject({
            let state = AppState()
            state.isAuthenticated = true
            state.currentUser = .preview
            state.organization = .preview
            return state
        }())
}
