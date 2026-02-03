import SwiftUI

/// Seyir tarihi/saati seçici görünümü
struct DeparturePickerView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedDate: Date
    let onStartNow: () -> Void
    let onStartScheduled: (Date) -> Void

    @State private var useScheduledTime = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header icon
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                    .padding(.top, 20)

                Text("Seyir Zamani")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Seyire hemen baslamak veya planlanan bir zaman secmek icin asagidaki secenekleri kullanin.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Mode toggle
                Picker("Zaman Secimi", selection: $useScheduledTime) {
                    Text("Hemen Basla").tag(false)
                    Text("Zaman Sec").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if useScheduledTime {
                    // Date picker section
                    VStack(spacing: 16) {
                        // Date picker
                        DatePicker(
                            "Tarih",
                            selection: $selectedDate,
                            in: Date()...,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .padding(.horizontal)

                        Divider()
                            .padding(.horizontal)

                        // Time picker
                        DatePicker(
                            "Saat",
                            selection: $selectedDate,
                            displayedComponents: [.hourAndMinute]
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(height: 100)

                        // Selected time display
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(.blue)
                            Text("Secilen: \(selectedDate.dateTimeStringTR)")
                                .fontWeight(.medium)
                        }
                        .padding()
                        .background(.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    if useScheduledTime {
                        Button {
                            onStartScheduled(selectedDate)
                            dismiss()
                        } label: {
                            Label("Planlanan Zamanda Basla", systemImage: "calendar.badge.checkmark")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.blue)
                                .foregroundStyle(.white)
                                .cornerRadius(14)
                        }
                    } else {
                        Button {
                            onStartNow()
                            dismiss()
                        } label: {
                            Label("Hemen Basla", systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.green)
                                .foregroundStyle(.white)
                                .cornerRadius(14)
                        }
                    }

                    Button("Iptal", role: .cancel) {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .animation(.easeInOut(duration: 0.3), value: useScheduledTime)
            .navigationTitle("Seyir Baslat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    DeparturePickerView(
        selectedDate: .constant(Date()),
        onStartNow: { print("Start now") },
        onStartScheduled: { date in print("Start at \(date)") }
    )
}
