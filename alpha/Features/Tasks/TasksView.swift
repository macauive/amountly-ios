//
//  TasksView.swift
//  alpha
//
//  Created by Claude Code on 12/16/25.
//

import SwiftUI
import Combine

// MARK: - Data Models for Grouping

struct ProjectGroup: Identifiable {
    let id: String
    let project: Project
    let totalHours: Double
    let totalAmount: Double?
    var taskGroups: [TaskGroup]
    var isExpanded: Bool = true

    var displayName: String {
        project.name
    }
}

struct TaskGroup: Identifiable {
    let id: String
    let task: ProjectTask?
    let taskName: String
    let totalHours: Double
    let totalAmount: Double?
    var entries: [TimeEntry]
    var isExpanded: Bool = false
}

// MARK: - Billing Period Enum

enum BillingPeriod: String, CaseIterable, Identifiable {
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case custom = "Custom"

    var id: String { rawValue }

    func dateRange() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .thisWeek:
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return (startOfWeek, now)

        case .thisMonth:
            let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            return (startOfMonth, now)

        case .lastMonth:
            let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            let startOfLastMonth = calendar.dateInterval(of: .month, for: lastMonth)?.start ?? now
            let endOfLastMonth = calendar.dateInterval(of: .month, for: lastMonth)?.end ?? now
            return (startOfLastMonth, endOfLastMonth)

        case .custom:
            // Default to this month for custom
            let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            return (startOfMonth, now)
        }
    }
}

// MARK: - ViewModel

@MainActor
class TasksViewModel: ObservableObject {
    @Published var timeEntries: [TimeEntry] = []
    @Published var projectGroups: [ProjectGroup] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var billingPeriod: BillingPeriod = .thisWeek
    @Published var customStartDate: Date = Date()
    @Published var customEndDate: Date = Date()

    // Summary metrics
    @Published var totalHours: Double = 0
    @Published var totalBillable: Double = 0
    @Published var projectsCount: Int = 0

    private let timeEntryRepository = TimeEntryRepository()

    // MARK: - Public Methods

    func loadTimeEntries() async {
        isLoading = true
        errorMessage = nil

        do {
            let dateRange = billingPeriod == .custom
                ? (start: customStartDate, end: customEndDate)
                : billingPeriod.dateRange()

            timeEntries = try await timeEntryRepository.fetchTimeEntries(
                startDate: dateRange.start,
                endDate: dateRange.end
            )

            groupEntries()
            calculateTotals()
        } catch {
            errorMessage = "Failed to load entries: \(error.localizedDescription)"
            timeEntries = []
            projectGroups = []
        }

        isLoading = false
    }

    func deleteEntry(_ entryId: String) async {
        do {
            try await timeEntryRepository.deleteTimeEntry(id: entryId)
            await loadTimeEntries()
        } catch {
            errorMessage = "Failed to delete entry: \(error.localizedDescription)"
        }
    }

    func toggleProjectExpanded(_ projectId: String) {
        if let index = projectGroups.firstIndex(where: { $0.id == projectId }) {
            projectGroups[index].isExpanded.toggle()
        }
    }

    func toggleTaskExpanded(projectId: String, taskId: String) {
        if let projectIndex = projectGroups.firstIndex(where: { $0.id == projectId }),
           let taskIndex = projectGroups[projectIndex].taskGroups.firstIndex(where: { $0.id == taskId }) {
            projectGroups[projectIndex].taskGroups[taskIndex].isExpanded.toggle()
        }
    }

    // MARK: - Private Methods

    private func groupEntries() {
        // Group by project first
        let projectDict = Dictionary(grouping: timeEntries) { $0.projectId ?? "unassigned" }

        projectGroups = projectDict.compactMap { projectId, entries in
            guard let firstEntry = entries.first else { return nil }

            // Group by task within project
            let taskDict = Dictionary(grouping: entries) { $0.taskId ?? "no_task" }

            let taskGroups = taskDict.map { taskId, taskEntries -> TaskGroup in
                let task = taskEntries.first?.task
                let taskName = task?.name ?? "No Task"
                let totalMinutes = taskEntries.reduce(0) { $0 + $1.durationMinutes }
                let totalHours = Double(totalMinutes) / 60.0

                // Calculate total amount for task
                let totalAmount: Double? = {
                    let amounts = taskEntries.compactMap { $0.billableAmount }
                    return amounts.isEmpty ? nil : amounts.reduce(0, +)
                }()

                return TaskGroup(
                    id: taskId,
                    task: task,
                    taskName: taskName,
                    totalHours: totalHours,
                    totalAmount: totalAmount,
                    entries: taskEntries,
                    isExpanded: false
                )
            }.sorted { $0.taskName < $1.taskName }

            // Calculate project totals
            let projectTotalMinutes = entries.reduce(0) { $0 + $1.durationMinutes }
            let projectTotalHours = Double(projectTotalMinutes) / 60.0

            let projectTotalAmount: Double? = {
                let amounts = entries.compactMap { $0.billableAmount }
                return amounts.isEmpty ? nil : amounts.reduce(0, +)
            }()

            return ProjectGroup(
                id: projectId,
                project: firstEntry.project ?? Project(
                    id: projectId,
                    organizationId: nil,
                    userId: nil,
                    clientId: nil,
                    name: "Unassigned Work",
                    description: nil,
                    billingModel: .hourly,
                    rate: nil,
                    budget: nil,
                    startDate: nil,
                    endDate: nil,
                    isActive: nil,
                    color: nil,
                    createdAt: nil,
                    updatedAt: nil,
                    client: nil,
                    tasks: nil
                ),
                totalHours: projectTotalHours,
                totalAmount: projectTotalAmount,
                taskGroups: taskGroups,
                isExpanded: true
            )
        }.sorted { $0.displayName < $1.displayName }
    }

    private func calculateTotals() {
        let totalMinutes = timeEntries.reduce(0) { $0 + $1.durationMinutes }
        totalHours = Double(totalMinutes) / 60.0

        let amounts = timeEntries.compactMap { $0.billableAmount }
        totalBillable = amounts.reduce(0, +)

        projectsCount = projectGroups.count
    }
}

// MARK: - TasksView

struct TasksView: View {
    @StateObject private var viewModel = TasksViewModel()
    @State private var editingEntry: TimeEntry?
    @State private var showingEditSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Billing Period Picker
                    BillingPeriodPicker(
                        selectedPeriod: $viewModel.billingPeriod,
                        customStartDate: $viewModel.customStartDate,
                        customEndDate: $viewModel.customEndDate
                    )
                    .padding(.horizontal)

                    // Summary Cards
                    HStack(spacing: 12) {
                        SummaryCard(
                            title: "Total Hours",
                            value: String(format: "%.1fh", viewModel.totalHours),
                            icon: "clock.fill",
                            color: .blue
                        )

                        SummaryCard(
                            title: "Total Billable",
                            value: String(format: "$%.0f", viewModel.totalBillable),
                            icon: "dollarsign.circle.fill",
                            color: .green
                        )

                        SummaryCard(
                            title: "Projects",
                            value: "\(viewModel.projectsCount)",
                            icon: "folder.fill",
                            color: .orange
                        )
                    }
                    .padding(.horizontal)

                    // Grouped Entries
                    if viewModel.isLoading {
                        ProgressView()
                            .padding(.top, 40)
                    } else if viewModel.projectGroups.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.projectGroups) { projectGroup in
                                ProjectGroupView(
                                    projectGroup: projectGroup,
                                    onToggleProject: {
                                        viewModel.toggleProjectExpanded(projectGroup.id)
                                    },
                                    onToggleTask: { taskId in
                                        viewModel.toggleTaskExpanded(projectId: projectGroup.id, taskId: taskId)
                                    },
                                    onDeleteEntry: { entryId in
                                        Task {
                                            await viewModel.deleteEntry(entryId)
                                        }
                                    },
                                    onEditEntry: { entry in
                                        editingEntry = entry
                                        showingEditSheet = true
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .background(Color.alphaGroupedBackground)
            .navigationTitle("Time Entries")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await viewModel.loadTimeEntries()
            }
            .task {
                await viewModel.loadTimeEntries()
            }
            .onChange(of: viewModel.billingPeriod) { _, _ in
                Task {
                    await viewModel.loadTimeEntries()
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                if let entry = editingEntry {
                    TimeEntryFormSheet(
                        isPresented: $showingEditSheet,
                        existingEntry: entry,
                        onSave: {
                            Task {
                                await viewModel.loadTimeEntries()
                            }
                        }
                    )
                    .withAppTheme()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.alphaSecondaryText)

            Text("No time entries")
                .font(.alphaBody)
                .foregroundColor(.alphaSecondaryText)

            Text("Tap + to create your first time entry")
                .font(.alphaBodySmall)
                .foregroundColor(.alphaTertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Summary Card Component

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.alphaPrimaryText)

            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.alphaSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.alphaCardBackground)
        .cornerRadius(12)
    }
}

// MARK: - Billing Period Picker Component

struct BillingPeriodPicker: View {
    @Binding var selectedPeriod: BillingPeriod
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    @State private var showingCustomPicker = false

    var body: some View {
        VStack(spacing: 12) {
            Picker("Billing Period", selection: $selectedPeriod) {
                ForEach(BillingPeriod.allCases) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)

            if selectedPeriod == .custom {
                HStack(spacing: 12) {
                    DatePicker("Start", selection: $customStartDate, displayedComponents: .date)
                        .labelsHidden()

                    Text("to")
                        .foregroundColor(.alphaSecondaryText)

                    DatePicker("End", selection: $customEndDate, displayedComponents: .date)
                        .labelsHidden()
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - ProjectGroupView Placeholder

struct ProjectGroupView: View {
    let projectGroup: ProjectGroup
    let onToggleProject: () -> Void
    let onToggleTask: (String) -> Void
    let onDeleteEntry: (String) -> Void
    let onEditEntry: (TimeEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Project Header
            Button(action: onToggleProject) {
                HStack {
                    Circle()
                        .fill(Color(hex: projectGroup.project.color ?? "#007AFF"))
                        .frame(width: 12, height: 12)

                    Text(projectGroup.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.alphaPrimaryText)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1fh", projectGroup.totalHours))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.alphaPrimaryText)

                        if let amount = projectGroup.totalAmount {
                            Text(String(format: "$%.0f", amount))
                                .font(.system(size: 12))
                                .foregroundColor(.alphaSecondaryText)
                        }
                    }

                    Image(systemName: projectGroup.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.alphaSecondaryText)
                        .frame(width: 20)
                }
                .padding()
                .background(Color.alphaCardBackground)
            }
            .buttonStyle(.plain)

            // Task Groups (when expanded)
            if projectGroup.isExpanded {
                ForEach(projectGroup.taskGroups) { taskGroup in
                    TaskGroupView(
                        taskGroup: taskGroup,
                        onToggle: { onToggleTask(taskGroup.id) },
                        onDeleteEntry: onDeleteEntry,
                        onEditEntry: onEditEntry
                    )
                }
            }
        }
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - TaskGroupView Placeholder

struct TaskGroupView: View {
    let taskGroup: TaskGroup
    let onToggle: () -> Void
    let onDeleteEntry: (String) -> Void
    let onEditEntry: (TimeEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack {
                    Text(taskGroup.taskName)
                        .font(.system(size: 14))
                        .foregroundColor(.alphaPrimaryText)
                        .padding(.leading, 24)

                    Spacer()

                    Text(String(format: "%.1fh", taskGroup.totalHours))
                        .font(.system(size: 12))
                        .foregroundColor(.alphaSecondaryText)

                    Image(systemName: taskGroup.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.alphaSecondaryText)
                        .frame(width: 20)
                }
                .padding(.vertical, 12)
                .padding(.horizontal)
                .background(Color.alphaCardBackground.opacity(0.5))
            }
            .buttonStyle(.plain)

            if taskGroup.isExpanded {
                ForEach(taskGroup.entries) { entry in
                    TimeEntryRow(
                        entry: entry,
                        onDelete: { onDeleteEntry(entry.id) },
                        onEdit: { onEditEntry(entry) }
                    )
                    .padding(.leading, 48)
                }
            }
        }
    }
}

// MARK: - TimeEntryRow Placeholder

struct TimeEntryRow: View {
    let entry: TimeEntry
    let onDelete: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.timeRangeFormatted)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.alphaPrimaryText)

                    if let notes = entry.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: 11))
                            .foregroundColor(.alphaSecondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(entry.durationFormatted)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.alphaPrimaryText)

                    if let amount = entry.billableAmount {
                        Text(String(format: "$%.0f", amount))
                            .font(.system(size: 11))
                            .foregroundColor(.alphaSecondaryText)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.alphaSecondaryText)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(Color.alphaCardBackground.opacity(0.3))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Preview

#Preview("Tasks View") {
    TasksView()
}
