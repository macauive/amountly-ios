//
//  QuickEntryViewModel.swift
//  alpha
//
//  Created by Claude Code on 12/16/25.
//

import Foundation
import Combine

@MainActor
class QuickEntryViewModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var selectedProject: Project?
    @Published var tasks: [ProjectTask] = []
    @Published var selectedTask: ProjectTask?
    @Published var date: Date = Date()
    @Published var durationHours: Int = 1
    @Published var durationMinutes: Int = 0
    @Published var notes: String = ""
    @Published var smartTimeText = ""
    private var capturedInterval: (start: Date, end: Date, day: Date, minutes: Int)?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    private let projectRepository = ProjectRepository()
    private let timeEntryRepository = TimeEntryRepository()

    // MARK: - Computed Properties

    var canSave: Bool {
        selectedProject != nil && (1...1440).contains(totalDurationMinutes)
    }

    var totalDurationMinutes: Int {
        (durationHours * 60) + durationMinutes
    }

    // MARK: - Public Methods

    func loadProjects() async {
        isLoading = true
        errorMessage = nil

        do {
            projects = try await projectRepository.fetchProjects()
            print("✅ Successfully loaded \(projects.count) projects")
        } catch {
            print("❌ Load projects error: \(error)")
            errorMessage = "Failed to load projects: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func loadTasks(for projectId: String) async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch project with tasks included
            let project = try await projectRepository.fetchProject(id: projectId)
            tasks = project.tasks ?? []
        } catch {
            errorMessage = "Failed to load tasks: \(error.localizedDescription)"
            tasks = []
        }

        isLoading = false
    }

    func onProjectSelected(_ project: Project?) async {
        selectedProject = project
        selectedTask = nil
        tasks = []

        if let projectId = project?.id {
            await loadTasks(for: projectId)
        }
    }

    var suggestedInterval: (start: Date, end: Date)? {
        guard let capturedInterval, capturedInterval.minutes == totalDurationMinutes,
              Calendar.current.isDate(capturedInterval.day, inSameDayAs: date) else { return nil }
        return (capturedInterval.start, capturedInterval.end)
    }
    func applySmartTime(_ result: AITime) {
        if let day = AIValidation.date(result.date) { date = day }
        durationHours = result.minutes / 60
        durationMinutes = result.minutes % 60
        if !result.notes.isEmpty { notes = result.notes }
        if let (start, end) = result.interval(referenceDate: date) {
            let exactMinutes = Int(end.timeIntervalSince(start) / 60)
            durationHours = exactMinutes / 60; durationMinutes = exactMinutes % 60
            capturedInterval = (start, end, date, exactMinutes)
        } else { capturedInterval = nil }
    }

    func saveEntry() async -> Bool {
        guard canSave else { return false }

        isSaving = true
        errorMessage = nil

        do {
            guard let projectId = selectedProject?.id else {
                errorMessage = "Please select a project"
                isSaving = false
                return false
            }

            // Calculate start and end times based on date and duration
            let calendar = Calendar.current
            let endTime = suggestedInterval?.end ?? calendar.date(bySettingHour: calendar.component(.hour, from: Date()),
                                       minute: calendar.component(.minute, from: Date()),
                                       second: 0,
                                       of: date) ?? date
            let startTime = suggestedInterval?.start ?? endTime.addingTimeInterval(-Double(totalDurationMinutes * 60))

            _ = try await timeEntryRepository.createTimeEntry(
                projectId: projectId,
                taskId: selectedTask?.id,
                startAt: startTime,
                endAt: endTime,
                durationMinutes: totalDurationMinutes,
                notes: notes.isEmpty ? nil : notes,
                source: "MOBILE"
            )

            // Reset form on success
            resetForm()
            isSaving = false
            return true

        } catch {
            errorMessage = "Failed to save time entry: \(error.localizedDescription)"
            isSaving = false
            return false
        }
    }

    func resetForm() {
        selectedProject = nil
        selectedTask = nil
        tasks = []
        date = Date()
        durationHours = 1
        durationMinutes = 0
        notes = ""
        smartTimeText = ""
        capturedInterval = nil
        errorMessage = nil
    }


}
