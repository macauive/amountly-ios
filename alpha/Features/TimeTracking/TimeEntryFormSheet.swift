//
//  TimeEntryFormSheet.swift
//  alpha
//
//  Created by Claude Code on 2/1/26.
//

import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
class TimeEntryFormViewModel: ObservableObject {
    // Form Fields
    @Published var selectedProject: Project?
    @Published var selectedTask: ProjectTask?
    @Published var date: Date = Date()
    @Published var startTime: Date = Date()
    @Published var endTime: Date = Date()
    @Published var notes: String = ""
    @Published var billableRateOverride: String = ""
    @Published var useBillableRateOverride = false
    @Published var smartTimeText = ""
    @Published var endsNextDay = false

    // Data
    @Published var projects: [Project] = []
    @Published var tasks: [ProjectTask] = []

    // State
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    // Editing mode
    let existingEntry: TimeEntry?
    private let projectRepository = ProjectRepository()
    private let timeEntryRepository = TimeEntryRepository()

    // MARK: - Computed Properties

    var isEditing: Bool {
        existingEntry != nil
    }

    var canSave: Bool {
        selectedProject != nil && (1...1440).contains(durationMinutes)
    }

    private var selectedInterval: (Date, Date)? {
        let calendar = Calendar.current
        guard let start = calendar.date(bySettingHour: calendar.component(.hour, from: startTime), minute: calendar.component(.minute, from: startTime), second: 0, of: date),
              let endDay = calendar.date(byAdding: .day, value: endsNextDay ? 1 : 0, to: date),
              let end = calendar.date(bySettingHour: calendar.component(.hour, from: endTime), minute: calendar.component(.minute, from: endTime), second: 0, of: endDay) else { return nil }
        return (start, end)
    }
    var durationMinutes: Int {
        guard let (start, end) = selectedInterval else { return 0 }
        return max(0, Int(end.timeIntervalSince(start) / 60))
    }

    var durationFormatted: String {
        let hours = durationMinutes / 60
        let minutes = durationMinutes % 60

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "0m"
        }
    }

    var effectiveBillableRate: Double? {
        if useBillableRateOverride, let rate = Double(billableRateOverride), rate > 0 {
            return rate
        }
        return selectedTask?.rate ?? selectedProject?.rate
    }

    var estimatedAmount: Double? {
        guard let rate = effectiveBillableRate else { return nil }
        return rate * (Double(durationMinutes) / 60.0)
    }

    var projectRate: String {
        if let rate = selectedTask?.rate {
            return String(format: "$%.2f/hr (task rate)", rate)
        } else if let rate = selectedProject?.rate {
            return String(format: "$%.2f/hr (project rate)", rate)
        }
        return "No rate set"
    }

    // MARK: - Init

    init(existingEntry: TimeEntry? = nil) {
        self.existingEntry = existingEntry

        if let entry = existingEntry {
            // Populate form with existing entry data
            self.date = entry.startAt
            self.startTime = entry.startAt
            self.endTime = entry.endAt
            self.endsNextDay = !Calendar.current.isDate(entry.startAt, inSameDayAs: entry.endAt)
            self.notes = entry.notes ?? ""

            if let rate = entry.billableRate {
                self.billableRateOverride = String(format: "%.2f", rate)
                self.useBillableRateOverride = true
            }
        } else {
            // Set default times for new entry (last hour)
            let now = Date()
            self.endTime = now
            self.startTime = now.addingTimeInterval(-3600) // 1 hour ago
        }
    }

    // MARK: - Public Methods

    func loadProjects() async {
        isLoading = true
        errorMessage = nil

        do {
            projects = try await projectRepository.fetchProjects()

            // If editing, set the selected project
            if let entry = existingEntry, let projectId = projects.first(where: { $0.id == entry.projectId })?.id {
                selectedProject = projects.first { $0.id == projectId }
                await loadTasks(for: projectId)

                // Set selected task if exists
                if let taskId = entry.taskId {
                    selectedTask = tasks.first { $0.id == taskId }
                }
            }
        } catch {
            errorMessage = "Failed to load projects: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func loadTasks(for projectId: String) async {
        do {
            let project = try await projectRepository.fetchProject(id: projectId)
            tasks = project.tasks ?? []
        } catch {
            tasks = []
        }
    }

    func onProjectSelected(_ project: Project?) async {
        selectedProject = project
        selectedTask = nil
        tasks = []

        if let projectId = project?.id {
            await loadTasks(for: projectId)
        }
    }

    func applySmartTime(_ result: AITime) {
        if let interval = result.interval(referenceDate: date) {
            date = interval.0; startTime = interval.0; endTime = interval.1
            endsNextDay = !Calendar.current.isDate(interval.0, inSameDayAs: interval.1)
        } else {
            if let foundDate = AIValidation.date(result.date) { date = foundDate }
            endTime = startTime; endsNextDay = false
        }
        if !result.notes.isEmpty { notes = result.notes }
    }

    func save() async -> Bool {
        guard canSave else { return false }
        guard let project = selectedProject else { return false }

        isSaving = true
        errorMessage = nil

        do {
            guard let (finalStartTime, finalEndTime) = selectedInterval else {
                errorMessage = "Invalid time selection"; isSaving = false; return false
            }

            let billableRate = useBillableRateOverride ? Double(billableRateOverride) : nil

            if let existingId = existingEntry?.id {
                // Update existing entry
                _ = try await timeEntryRepository.updateTimeEntry(
                    id: existingId,
                    projectId: project.id,
                    taskId: selectedTask?.id,
                    startAt: finalStartTime,
                    endAt: finalEndTime,
                    durationMinutes: durationMinutes,
                    notes: notes.isEmpty ? nil : notes,
                    billableRate: billableRate
                )
            } else {
                // Create new entry
                _ = try await timeEntryRepository.createTimeEntry(
                    projectId: project.id,
                    taskId: selectedTask?.id,
                    startAt: finalStartTime,
                    endAt: finalEndTime,
                    durationMinutes: durationMinutes,
                    notes: notes.isEmpty ? nil : notes,
                    source: "MOBILE"
                )
            }

            isSaving = false
            return true

        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            isSaving = false
            return false
        }
    }
}

// MARK: - TimeEntryFormSheet

struct TimeEntryFormSheet: View {
    @Binding var isPresented: Bool
    var existingEntry: TimeEntry?
    var onSave: (() -> Void)?

    @StateObject private var viewModel: TimeEntryFormViewModel

    init(isPresented: Binding<Bool>, existingEntry: TimeEntry? = nil, onSave: (() -> Void)? = nil) {
        self._isPresented = isPresented
        self.existingEntry = existingEntry
        self.onSave = onSave
        self._viewModel = StateObject(wrappedValue: TimeEntryFormViewModel(existingEntry: existingEntry))
    }

    var body: some View {
        NavigationStack {
            Form {
                AICaptureSection<AITime>(title: "Smart time capture", text: $viewModel.smartTimeText, task: .time, apply: viewModel.applySmartTime)
                    .disabled(viewModel.isSaving)

                Section { Toggle("Ends next day", isOn: $viewModel.endsNextDay) }

                // Project Selection
                Section {
                    Picker("Project", selection: Binding(
                        get: { viewModel.selectedProject },
                        set: { newValue in
                            Task {
                                await viewModel.onProjectSelected(newValue)
                            }
                        }
                    )) {
                        Text("Select Project")
                            .foregroundColor(.secondary)
                            .tag(nil as Project?)
                        ForEach(viewModel.projects) { project in
                            HStack {
                                if let color = project.color {
                                    Circle()
                                        .fill(Color(hex: color))
                                        .frame(width: 10, height: 10)
                                }
                                Text(project.name)
                            }
                            .tag(project as Project?)
                        }
                    }
                    .disabled(viewModel.isLoading || viewModel.isSaving)

                    if let project = viewModel.selectedProject {
                        HStack {
                            Text("Client")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(project.client?.name ?? "No client")
                                .foregroundColor(.secondary)
                        }
                        .font(.system(size: 14))
                    }
                } header: {
                    Text("Project")
                }

                // Task Selection
                if viewModel.selectedProject != nil {
                    Section {
                        Picker("Task", selection: $viewModel.selectedTask) {
                            Text("No Task")
                                .foregroundColor(.secondary)
                                .tag(nil as ProjectTask?)
                            ForEach(viewModel.tasks) { task in
                                Text(task.name).tag(task as ProjectTask?)
                            }
                        }
                        .disabled(viewModel.isLoading || viewModel.isSaving)
                    } header: {
                        Text("Task (Optional)")
                    }
                }

                // Date & Time
                Section {
                    DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)
                        .disabled(viewModel.isSaving)

                    DatePicker("Start Time", selection: $viewModel.startTime, displayedComponents: .hourAndMinute)
                        .disabled(viewModel.isSaving)

                    DatePicker("End Time", selection: $viewModel.endTime, displayedComponents: .hourAndMinute)
                        .disabled(viewModel.isSaving)

                    HStack {
                        Text("Duration")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(viewModel.durationFormatted)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(viewModel.durationMinutes > 0 ? .primary : .red)
                    }
                } header: {
                    Text("Date & Time")
                }

                // Billing
                Section {
                    HStack {
                        Text("Default Rate")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(viewModel.projectRate)
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }

                    Toggle("Override Billable Rate", isOn: $viewModel.useBillableRateOverride)
                        .disabled(viewModel.isSaving)

                    if viewModel.useBillableRateOverride {
                        HStack {
                            Text("$")
                            TextField("Rate", text: $viewModel.billableRateOverride)
                                .keyboardType(.decimalPad)
                            Text("/hr")
                                .foregroundColor(.secondary)
                        }
                        .disabled(viewModel.isSaving)
                    }

                    if let amount = viewModel.estimatedAmount {
                        HStack {
                            Text("Estimated Amount")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "$%.2f", amount))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.alphaSuccess)
                        }
                    }
                } header: {
                    Text("Billing")
                }

                // Notes
                Section {
                    TextField("What did you work on?", text: $viewModel.notes, axis: .vertical)
                        .lineLimit(3...6)
                        .disabled(viewModel.isSaving)
                } header: {
                    Text("Notes (Optional)")
                }

                // Error Message
                if let errorMessage = viewModel.errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle(viewModel.isEditing ? "Edit Time Entry" : "Log Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .disabled(viewModel.isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isEditing ? "Save" : "Log") {
                        Task {
                            let success = await viewModel.save()
                            if success {
                                onSave?()
                                isPresented = false
                            }
                        }
                    }
                    .disabled(!viewModel.canSave || viewModel.isSaving)
                }
            }
            .overlay {
                if viewModel.isSaving {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()

                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text(viewModel.isEditing ? "Saving..." : "Logging time...")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                        }
                        .padding(24)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(12)
                        .shadow(radius: 10)
                    }
                }
            }
            .task {
                await viewModel.loadProjects()
            }
        }
    }
}

// MARK: - Preview

#Preview("New Time Entry") {
    TimeEntryFormSheet(isPresented: .constant(true))
}

#Preview("Edit Time Entry") {
    TimeEntryFormSheet(isPresented: .constant(true), existingEntry: .preview)
}
