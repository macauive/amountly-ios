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
    @Published var smartTimeSummary: String?

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
        selectedProject != nil && durationMinutes > 0
    }

    var durationMinutes: Int {
        let interval = endTime.timeIntervalSince(startTime)
        return max(0, Int(interval / 60))
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

    func fillFromSmartTime() {
        let result = TimeCaptureParser.capture(from: smartTimeText)
        date = result.date
        startTime = result.startTime
        endTime = result.endTime

        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes = result.notes
        }

        smartTimeSummary = result.reason
    }

    func save() async -> Bool {
        guard canSave else { return false }
        guard let project = selectedProject else { return false }

        isSaving = true
        errorMessage = nil

        do {
            // Combine date with times
            let calendar = Calendar.current
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
            let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
            let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)

            var startDateComponents = dateComponents
            startDateComponents.hour = startComponents.hour
            startDateComponents.minute = startComponents.minute

            var endDateComponents = dateComponents
            endDateComponents.hour = endComponents.hour
            endDateComponents.minute = endComponents.minute

            guard let finalStartTime = calendar.date(from: startDateComponents),
                  let finalEndTime = calendar.date(from: endDateComponents) else {
                errorMessage = "Invalid time selection"
                isSaving = false
                return false
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
                if !viewModel.isEditing {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.alphaPrimary)
                                    .frame(width: 32, height: 32)
                                    .background(Color.alphaPrimary.opacity(0.1))
                                    .cornerRadius(8)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Smart time capture")
                                        .font(.alphaBodyMedium)
                                        .foregroundColor(.alphaPrimaryText)

                                    Text("Describe the work and Alpha will fill the time entry.")
                                        .font(.alphaBodySmall)
                                        .foregroundColor(.alphaSecondaryText)
                                }
                            }

                            TextEditor(text: $viewModel.smartTimeText)
                                .frame(minHeight: 96)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.alphaBorder.opacity(0.5), lineWidth: 1)
                                )
                                .disabled(viewModel.isSaving)
                                .accessibilityLabel("Smart time text")

                            HStack(alignment: .top, spacing: 12) {
                                Text(viewModel.smartTimeSummary ?? "Alpha looks for work notes, dates, durations, and time ranges.")
                                    .font(.alphaCaption)
                                    .foregroundColor(.alphaSecondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    viewModel.fillFromSmartTime()
                                } label: {
                                    Label("Fill time entry", systemImage: "wand.and.stars")
                                }
                                .font(.alphaCaption)
                                .disabled(viewModel.smartTimeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSaving)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

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

struct TimeCaptureResult {
    let date: Date
    let startTime: Date
    let endTime: Date
    let notes: String
    let durationMinutes: Int
    let reason: String
}

enum TimeCaptureParser {
    nonisolated static func capture(from text: String, referenceDate: Date = Date()) -> TimeCaptureResult {
        let calendar = Calendar.current
        let baseDate = parseDate(from: text, referenceDate: referenceDate, calendar: calendar)
        let range = parseTimeRange(from: text)
        let durationMinutes = range.map { $0.end - $0.start } ?? parseDurationMinutes(from: text)
        let startMinutes = range?.start ?? 9 * 60
        let endMinutes = range?.end ?? startMinutes + durationMinutes
        let notes = titleCaseFirst(cleanNotes(from: text).nilIfEmpty ?? "Work session")

        return TimeCaptureResult(
            date: baseDate,
            startTime: date(on: baseDate, minutesFromMidnight: startMinutes, calendar: calendar),
            endTime: date(on: baseDate, minutesFromMidnight: endMinutes, calendar: calendar),
            notes: notes,
            durationMinutes: durationMinutes,
            reason: range == nil
                ? "Alpha found a duration and estimated the time block."
                : "Alpha found a start and end time in your note."
        )
    }

    nonisolated private static func parseDate(from text: String, referenceDate: Date, calendar: Calendar) -> Date {
        let normalized = text.lowercased()
        if normalized.contains("yesterday"),
           let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate) {
            return yesterday
        }

        if normalized.contains("today") {
            return referenceDate
        }

        if let components = firstDateComponents(
            in: text,
            pattern: #"\b(20\d{2})[-/](0?[1-9]|1[0-2])[-/](0?[1-9]|[12]\d|3[01])\b"#,
            order: [.year, .month, .day]
        ) {
            return calendar.date(from: components) ?? referenceDate
        }

        if let components = firstDateComponents(
            in: text,
            pattern: #"\b(0?[1-9]|1[0-2])[-/](0?[1-9]|[12]\d|3[01])[-/](20\d{2})\b"#,
            order: [.month, .day, .year]
        ) {
            return calendar.date(from: components) ?? referenceDate
        }

        return referenceDate
    }

    nonisolated private static func parseTimeRange(from text: String) -> (start: Int, end: Int)? {
        let pattern = #"\b(?:from\s*)?([01]?\d|2[0-3])(?::([0-5]\d))?\s*(am|pm)?\s*(?:-|to)\s*([01]?\d|2[0-3])(?::([0-5]\d))?\s*(am|pm)?\b"#
        guard let groups = firstGroups(in: text, pattern: pattern, options: [.caseInsensitive]), groups.count >= 7 else {
            return nil
        }

        let start = parseTime(hour: groups[1], minute: groups[2], meridiem: groups[3])
        let end = parseTime(hour: groups[4], minute: groups[5], meridiem: groups[6].nilIfEmpty ?? groups[3])

        guard let start, let end, end > start else { return nil }
        return (start, end)
    }

    nonisolated private static func parseDurationMinutes(from text: String) -> Int {
        if let groups = firstGroups(in: text, pattern: #"\b(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|h)\b"#, options: [.caseInsensitive]),
           let value = Double(groups[1]) {
            return Int((value * 60).rounded())
        }

        if let groups = firstGroups(in: text, pattern: #"\b(\d+)\s*(?:minutes?|mins?|m)\b"#, options: [.caseInsensitive]),
           let value = Int(groups[1]) {
            return value
        }

        return 60
    }

    nonisolated private static func cleanNotes(from text: String) -> String {
        text
            .replacingOccurrences(
                of: #"\b(?:from\s*)?([01]?\d|2[0-3])(?::([0-5]\d))?\s*(am|pm)?\s*(?:-|to)\s*([01]?\d|2[0-3])(?::([0-5]\d))?\s*(am|pm)?\b"#,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"\b\d+(?:\.\d+)?\s*(?:hours?|hrs?|h|minutes?|mins?|m)\b"#,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(of: #"\b(today|yesterday)\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(20\d{2})[-/](0?[1-9]|1[0-2])[-/](0?[1-9]|[12]\d|3[01])\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b(0?[1-9]|1[0-2])[-/](0?[1-9]|[12]\d|3[01])[-/](20\d{2})\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func parseTime(hour: String, minute: String, meridiem: String) -> Int? {
        guard var hours = Int(hour) else { return nil }
        let minutes = Int(minute.nilIfEmpty ?? "0") ?? 0
        let normalizedMeridiem = meridiem.lowercased()

        if normalizedMeridiem == "pm", hours < 12 {
            hours += 12
        }
        if normalizedMeridiem == "am", hours == 12 {
            hours = 0
        }

        return hours * 60 + minutes
    }

    nonisolated private static func date(on day: Date, minutesFromMidnight: Int, calendar: Calendar) -> Date {
        let hour = minutesFromMidnight / 60
        let minute = minutesFromMidnight % 60
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? day
    }

    nonisolated private static func titleCaseFirst(_ value: String) -> String {
        guard let first = value.first else { return value }
        return first.uppercased() + value.dropFirst()
    }

    nonisolated private static func firstDateComponents(
        in text: String,
        pattern: String,
        order: [Calendar.Component]
    ) -> DateComponents? {
        guard let groups = firstGroups(in: text, pattern: pattern), groups.count == 4 else { return nil }

        var components = DateComponents()
        for (index, component) in order.enumerated() {
            let value = Int(groups[index + 1])
            switch component {
            case .year:
                components.year = value
            case .month:
                components.month = value
            case .day:
                components.day = value
            default:
                break
            }
        }

        return components
    }

    nonisolated private static func firstGroups(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }

        return (0..<match.numberOfRanges).map { index in
            guard let groupRange = Range(match.range(at: index), in: text) else { return "" }
            return String(text[groupRange])
        }
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Preview

#Preview("New Time Entry") {
    TimeEntryFormSheet(isPresented: .constant(true))
}

#Preview("Edit Time Entry") {
    TimeEntryFormSheet(isPresented: .constant(true), existingEntry: .preview)
}
