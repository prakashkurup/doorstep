import SwiftUI

/// The next seven days with a dot per expected delivery. Click a day to see only its
/// packages; click it again (or "Show all") to go back.
struct WeekStrip: View {
    @Environment(OrderStore.self) private var store

    var body: some View {
        HStack(spacing: 2) {
            ForEach(store.weekDays, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let cal = Calendar.current
        let arrivals = store.arrivals(on: day)
        let isToday = cal.isDateInToday(day)
        let selected = store.selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false
        let outToday = isToday && arrivals.contains { $0.status == .outForDelivery }
        let dotColor = outToday ? Palette.orange : Palette.blue

        return Button {
            withAnimation(.snappy(duration: 0.2)) { store.selectedDay = selected ? nil : day }
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 13, weight: isToday ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Palette.blue : .primary)
                HStack(spacing: 2) {
                    ForEach(0..<min(arrivals.count, 3), id: \.self) { _ in
                        Circle().fill(dotColor).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if selected {
                    Color.clear.glassEffect(.regular.tint(Palette.blue.opacity(0.28)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(HoverButtonStyle(cornerRadius: 9))
        .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).month().day())), \(arrivals.count) \(arrivals.count == 1 ? "delivery" : "deliveries")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
