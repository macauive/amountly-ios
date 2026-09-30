//
//  QuickEntrySheet.swift
//  alpha
//
//  Created by Claude Code on 12/16/25.
//

import SwiftUI

struct QuickEntrySheet: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel = QuickEntryViewModel()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                AICaptureSection<AITime>(title: "Smart time capture", text: $viewModel.smartTimeText, task: .time, apply: viewModel.applySmartTime)
                    .disabled(viewModel.isSaving)
                if let interval = viewModel.suggestedInterval {
                    Section("Suggested time block") {
                        Text("\(interval.start.formatted(date: .abbreviated, time: .shortened)) – \(interval.end.formatted(date: .abbreviated, time: .shortened))")
                        Text("Changing the date or duration uses a new estimated time block.").font(.caption)
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
                            .foregroundColor(.alphaSecondaryText)
                            .tag(nil as Project?)
                        ForEach(viewModel.projects) { project in
                            HStack {
                                if let color = project.color {
                                    Circle()
                                        .fill(Color(hex: color))
                                        .frame(width: 8, height: 8)
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
                                .foregroundColor(.alphaSecondaryText)
                            Spacer()
                            Text(project.client?.name ?? "No client")
                                .foregroundColor(.alphaTertiaryText)
                        }
                        .font(.alphaBodySmall)
                    }
                } header: {
                    Text("Project")
                }

                // Task Selection
                if viewModel.selectedProject != nil {
                    Section {
                        Picker("Task", selection: $viewModel.selectedTask) {
                            Text("No Task")
                                .foregroundColor(.alphaSecondaryText)
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

                // Date Selection
                Section {
                    DatePicker(
                        "Date",
                        selection: $viewModel.date,
                        displayedComponents: .date
                    )
                    .disabled(viewModel.isSaving)
                } header: {
                    Text("Date")
                }

                // Duration Selection
                Section {
                    HStack {
                        Picker("Hours", selection: $viewModel.durationHours) {
                            ForEach(0..<25) { hour in
                                Text("\(hour)h").tag(hour)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)

                        Picker("Minutes", selection: $viewModel.durationMinutes) {
                            ForEach(Array(0..<60), id: \.self) { minute in
                                Text("\(minute)m").tag(minute)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 120)
                    .disabled(viewModel.isSaving)

                    HStack {
                        Text("Total")
                            .foregroundColor(.alphaSecondaryText)
                        Spacer()
                        Text(formatDuration(viewModel.totalDurationMinutes))
                            .font(.alphaHeadline)
                            .foregroundColor(.alphaPrimary)
                    }
                } header: {
                    Text("Duration")
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
                                .foregroundColor(.alphaError)
                            Text(errorMessage)
                                .font(.alphaBodySmall)
                                .foregroundColor(.alphaError)
                        }
                    }
                }

                // Save Button
                Section {
                    AlphaButton(
                        "Save Time Entry",
                        style: .primary,
                        size: .large,
                        isLoading: viewModel.isSaving,
                        isDisabled: !viewModel.canSave
                    ) {
                        Task {
                            let success = await viewModel.saveEntry()
                            if success {
                                isPresented = false
                            }
                        }
                    }
                }
            }
            .navigationTitle("Log Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            .task {
                await viewModel.loadProjects()
            }
        }
    }

    // MARK: - Helper Methods

    private func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60

        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else if mins > 0 {
            return "\(mins)m"
        } else {
            return "0m"
        }
    }
}

// MARK: - Preview

#Preview("Quick Entry Sheet") {
    struct PreviewWrapper: View {
        @State private var isPresented = true

        var body: some View {
            Text("Main View")
                .sheet(isPresented: $isPresented) {
                    QuickEntrySheet(isPresented: $isPresented)
                }
        }
    }

    return PreviewWrapper()
}
