//
//  DisplaySettingsView.swift
//  alpha
//
//  Created by Claude Code on 12/17/25.
//

import SwiftUI

struct DisplaySettingsView: View {
    @AppStorage("appearance") private var appearance: String = "system"
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.inline)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.alphaLabel)
                        .foregroundColor(.alphaSecondaryText)

                    HStack(spacing: 12) {
                        // Light preview
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .frame(height: 80)
                                .overlay {
                                    VStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 24, height: 24)
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 40, height: 8)
                                    }
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                }

                            Text("Light")
                                .font(.alphaCaption)
                                .foregroundColor(.alphaSecondaryText)
                        }

                        // Dark preview
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black)
                                .frame(height: 80)
                                .overlay {
                                    VStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.white.opacity(0.3))
                                            .frame(width: 24, height: 24)
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.white.opacity(0.2))
                                            .frame(width: 40, height: 8)
                                    }
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                }

                            Text("Dark")
                                .font(.alphaCaption)
                                .foregroundColor(.alphaSecondaryText)
                        }
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("")
            } footer: {
                Text("Choose how Amountly looks on your device. System will match your device's appearance settings.")
                    .font(.alphaCaption)
                    .foregroundColor(.alphaSecondaryText)
            }
        }
        .navigationTitle("Display")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#Preview("Display Settings - Light") {
    NavigationStack {
        DisplaySettingsView()
    }
    .preferredColorScheme(.light)
}

#Preview("Display Settings - Dark") {
    NavigationStack {
        DisplaySettingsView()
    }
    .preferredColorScheme(.dark)
}
