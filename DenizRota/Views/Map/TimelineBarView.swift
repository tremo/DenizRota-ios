import SwiftUI

/// Windy-tarzi ince zaman cubugu - haritanin altinda gosterilir
/// Kullanici kaydirarak saat ve gun secer, hava durumu buna gore guncellenir
struct TimelineBarView: View {
    @Binding var selectedDate: Date
    let onDateChanged: (Date) -> Void

    @State private var hours: [Date] = []
    @State private var scrollTarget: Date?

    private let calendar = Calendar.current
    private let hourWidth: CGFloat = 44
    private let barHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            // Secilen zaman gostergesi
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(selectedDate.dateTimeStringTR)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                if isNow {
                    Text("Simdi")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.blue)
                        .clipShape(Capsule())
                }

                Spacer()

                // Simdiye don butonu
                if !isNow {
                    Button {
                        selectNow()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11))
                            .foregroundStyle(.blue)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            // Saat cubugu
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(hours, id: \.self) { hour in
                            TimelineHourCell(
                                hour: hour,
                                isSelected: isSameHour(hour, selectedDate),
                                isDayStart: calendar.component(.hour, from: hour) == 0,
                                isCurrentHour: isSameHour(hour, Date())
                            )
                            .frame(width: hourWidth)
                            .id(hour)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedDate = hour
                                }
                                onDateChanged(hour)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(height: 30)
                .onChange(of: scrollTarget) { _, newValue in
                    if let target = newValue {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                        scrollTarget = nil
                    }
                }
                .onAppear {
                    // Kisa gecikme ile scroll (layout tamamlansin)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo(closestHour(to: selectedDate), anchor: .center)
                    }
                }
            }
        }
        .frame(height: barHeight)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .onAppear {
            generateHours()
        }
    }

    // MARK: - Helpers

    private var isNow: Bool {
        abs(selectedDate.timeIntervalSince(closestHour(to: Date()))) < 1800
    }

    private func selectNow() {
        let now = closestHour(to: Date())
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedDate = now
        }
        scrollTarget = now
        onDateChanged(now)
    }

    private func generateHours() {
        let now = Date()
        let startHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        hours = (0..<72).compactMap { offset in
            calendar.date(byAdding: .hour, value: offset, to: startHour)
        }
    }

    private func closestHour(to date: Date) -> Date {
        let startOfHour = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        return startOfHour
    }

    private func isSameHour(_ a: Date, _ b: Date) -> Bool {
        calendar.component(.hour, from: a) == calendar.component(.hour, from: b) &&
        calendar.isDate(a, inSameDayAs: b)
    }
}

// MARK: - Hour Cell

private struct TimelineHourCell: View {
    let hour: Date
    let isSelected: Bool
    let isDayStart: Bool
    let isCurrentHour: Bool

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 1) {
            if isDayStart {
                // Gun etiketi
                Text(dayLabel)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else {
                // Saat
                Text(hourLabel)
                    .font(.system(size: 11, weight: isSelected ? .bold : .regular, design: .rounded))
                    .foregroundStyle(isSelected ? .white : isCurrentHour ? .blue : .secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.blue)
                } else if isCurrentHour {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.blue.opacity(0.1))
                }
            }
        )
        .padding(.horizontal, 1)
        .padding(.vertical, 2)
    }

    private var hourLabel: String {
        let h = calendar.component(.hour, from: hour)
        return String(format: "%02d", h)
    }

    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "EEE d"
        return formatter.string(from: hour)
    }
}

#Preview {
    VStack {
        Spacer()
        TimelineBarView(
            selectedDate: .constant(Date()),
            onDateChanged: { _ in }
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 80)
    }
    .background(Color.gray.opacity(0.3))
}
