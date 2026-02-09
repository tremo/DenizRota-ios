import SwiftUI

/// Windy-tarzi zaman cubugu - tab bar'in hemen ustunde gosterilir
/// Parmakla saga sola kaydirarak saat secilir, her saat degisiminde haptic feedback verilir
struct TimelineBarView: View {
    @Binding var selectedDate: Date
    let onDateChanged: (Date) -> Void

    @State private var hours: [Date] = []
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var lastSnappedIndex: Int = 0

    private let calendar = Calendar.current
    private let hourWidth: CGFloat = 48
    private let hapticFeedback = UISelectionFeedbackGenerator()

    var body: some View {
        VStack(spacing: 0) {
            // Ince ayirici cizgi
            Divider()

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

            // Kaydirmali saat cubugu
            GeometryReader { geo in
                let centerX = geo.size.width / 2

                ZStack {
                    // Merkez secim gostergesi (mavi alan)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.blue.opacity(0.15))
                        .frame(width: hourWidth - 4, height: 24)
                        .position(x: centerX, y: 13)

                    // Ust isaretci cizgi
                    Triangle()
                        .fill(.blue)
                        .frame(width: 8, height: 4)
                        .position(x: centerX, y: 1)

                    // Saat seridi
                    HStack(spacing: 0) {
                        ForEach(hours.indices, id: \.self) { index in
                            TimelineHourCell(
                                hour: hours[index],
                                isSelected: index == effectiveIndex,
                                isDayStart: calendar.component(.hour, from: hours[index]) == 0,
                                isCurrentHour: isSameHour(hours[index], Date())
                            )
                            .frame(width: hourWidth)
                        }
                    }
                    .offset(x: centerX - CGFloat(currentIndex) * hourWidth - hourWidth / 2 + dragOffset)
                    .gesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { value in
                                dragOffset = value.translation.width

                                // Surukleme sirasinda hangi saatte oldugunu hesapla
                                let proposedIndex = clampedIndex(currentIndex - Int(round(value.translation.width / hourWidth)))

                                if proposedIndex != lastSnappedIndex {
                                    hapticFeedback.selectionChanged()
                                    lastSnappedIndex = proposedIndex
                                    selectedDate = hours[proposedIndex]
                                }
                            }
                            .onEnded { value in
                                // Momentum hesabi: hiz + mevcut konum
                                let velocity = value.predictedEndTranslation.width - value.translation.width
                                let totalTranslation = value.translation.width + velocity * 0.3
                                let hoursMoved = -Int(round(totalTranslation / hourWidth))
                                let newIndex = clampedIndex(currentIndex + hoursMoved)

                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    currentIndex = newIndex
                                    dragOffset = 0
                                }

                                lastSnappedIndex = newIndex
                                selectedDate = hours[newIndex]
                                onDateChanged(hours[newIndex])
                            }
                    )
                }
                .clipped()
            }
            .frame(height: 28)
            .padding(.bottom, 2)
        }
        .background(.ultraThinMaterial)
        .onAppear {
            generateHours()
            hapticFeedback.prepare()
        }
    }

    // MARK: - Helpers

    /// Surukleme sirasinda hangi index'in secili oldugunu hesaplar
    private var effectiveIndex: Int {
        clampedIndex(currentIndex - Int(round(dragOffset / hourWidth)))
    }

    private var isNow: Bool {
        guard !hours.isEmpty else { return false }
        return abs(selectedDate.timeIntervalSince(closestHour(to: Date()))) < 1800
    }

    private func selectNow() {
        let now = closestHour(to: Date())
        if let index = hours.firstIndex(where: { isSameHour($0, now) }) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                currentIndex = index
                dragOffset = 0
            }
            lastSnappedIndex = index
            selectedDate = hours[index]
            onDateChanged(hours[index])
            hapticFeedback.selectionChanged()
        }
    }

    private func generateHours() {
        let now = Date()
        let startHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        hours = (0..<72).compactMap { offset in
            calendar.date(byAdding: .hour, value: offset, to: startHour)
        }
        // Baslangic index'ini secilen saate ayarla
        if let index = hours.firstIndex(where: { isSameHour($0, selectedDate) }) {
            currentIndex = index
            lastSnappedIndex = index
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

    private func clampedIndex(_ index: Int) -> Int {
        guard !hours.isEmpty else { return 0 }
        return max(0, min(hours.count - 1, index))
    }
}

// MARK: - Triangle Shape (merkez isaretci)

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
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
                    .foregroundStyle(isSelected ? .blue : isCurrentHour ? .blue : .secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }
    .background(Color.gray.opacity(0.3))
}
