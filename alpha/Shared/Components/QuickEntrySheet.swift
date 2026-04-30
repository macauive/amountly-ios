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
                            ForEach(0..<13) { hour in
                                Text("\(hour)h").tag(hour)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)

                        Picker("Minutes", selection: $viewModel.durationMinutes) {
                            ForEach([0, 15, 30, 45], id: \.self) { minute in
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
