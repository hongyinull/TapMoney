//
//  InsightsView.swift
//  talkmoney
//
//  Created by HONGYINULL on 2025/5/23.
//
// MARK: - 🔖 InsightsView 備忘錄（給未來使用此檔案的你）

/**
 本區為 ContentView.swift 中編寫 InsightsView（趨勢頁面）所需之完整備忘與設計指南。

 ✅ 資料模型結構（來自 SwiftData）

 @Model class ExpenseEntry: Identifiable {
     var id: UUID
     var icon: String
     var title: String
     var amount: Int         // 單筆金額（整數）
     var category: String    // 分類：飲食、購物、交通、娛樂、健康、生活、其他
     var timestamp: Date     // 消費時間，為 Date 型別（從 ISO8601 格式轉換）
     var note: String?       // 可選備註（可能包含情緒、用途描述）
 }

 ✅ 現有資料來源方式：

 在 ContentView 使用的是：
 @Query(sort: \ExpenseEntry.timestamp, order: .reverse) var entries: [ExpenseEntry]

 若欲在 InsightsView 中讀取資料，請使用類似方式：
 @Query var entries: [ExpenseEntry]
 → 可加上條件或排序，例如：
 @Query(filter: #Predicate<ExpenseEntry> { $0.timestamp > 一週前 }) var entries

 ✅ 時間格式工具（目前統一為台北時區）：

 - `preciseFormatter`: yyyy-MM-dd'T'HH:mmXXXXX（含秒、時區，用於資料存入）
 - `timeFormatter`: HH:mm（顯示時刻用）
 - `displayDateFormatter`: DateFormatter().dateStyle = .full
 - 若需更自由轉換請建立新 formatter

 ✅ InsightsView 可以考慮的分析與視覺化內容：

 1. 📊 類別統計圓餅圖（PieChart）
    - 可依 `category` 分組後加總 `amount`
    - 可設定時間範圍（本週、本月）

 2. 📈 時間趨勢圖（LineChart 或 BarChart）
    - x 軸為日期（可分日、週、月）
    - y 軸為每日總支出（amount 加總）

 3. 🏆 最常出現項目（熱門 icon 或 title）
    - 可統計出現次數最多的 title 或 emoji
    - 也可依花費金額排序前幾名

**/

import Foundation

import SwiftUI
import SwiftData
import Charts

// MARK: - InsightsView 主結構入口

struct InsightsView: View {
    @Query var entries: [ExpenseEntry]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                MonthlyCategoryPieChart(entries: entries)
                MonthlySpendingLineChart(entries: entries)
                CategoryAreaChart(entries: entries)
                DailySpendingBarChart(entries: entries)
                EntryFrequencyHeatmap(entries: entries)
                IncomeExpenseHeatmap(entries: entries)
            }
            .padding()
        }
        .navigationTitle("趨勢")
    }
}
// MARK: - MonthlySpendingLineChart

struct MonthlySpendingLineChart: View {
    let entries: [ExpenseEntry]
    @State private var selectedDate: Date?

    var dailyTotals: [(Date, Int)] {
        let grouped = Dictionary(grouping: entries, by: {
            Calendar.current.startOfDay(for: $0.timestamp)
        })
        return grouped.map { ($0.key, $0.value.map { $0.amount }.reduce(0, +)) }
            .filter { Calendar.current.isDate($0.0, equalTo: Date(), toGranularity: .month) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("每日支出趨勢")
                .font(.headline)
            Chart {
                ForEach(dailyTotals, id: \.0) { item in
                    LineMark(x: .value("日期", item.0), y: .value("金額", item.1))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("日期", item.0), y: .value("金額", item.1))
                }
                if let selected = selectedDate {
                    RuleMark(x: .value("Selected", selected))
                        .foregroundStyle(.gray)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture().onChanged { value in
                                if let date: Date = proxy.value(atX: value.location.x) {
                                    let nearest = dailyTotals.min(by: { abs($0.0.timeIntervalSince1970 - date.timeIntervalSince1970) < abs($1.0.timeIntervalSince1970 - date.timeIntervalSince1970) })?.0
                                    selectedDate = nearest
                                }
                            }
                        )
                }
            }
            .frame(height: 220)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.2)))
    }
}

// MARK: - CategoryAreaChart

struct CategoryAreaChart: View {
    let entries: [ExpenseEntry]

    var series: [(String, [(Date, Int)])] {
        let filtered = entries.filter {
            Calendar.current.isDate($0.timestamp, equalTo: Date(), toGranularity: .month)
        }
        let grouped = Dictionary(grouping: filtered, by: { $0.category })

        return grouped.map { category, items in
            let byDate = Dictionary(grouping: items, by: {
                Calendar.current.startOfDay(for: $0.timestamp)
            }).map { (date, values) in
                (date, values.map { $0.amount }.reduce(0, +))
            }.sorted { $0.0 < $1.0 }

            return (category, byDate)
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("分類支出區域圖")
                .font(.headline)
            Chart {
                ForEach(Array(series.enumerated()), id: \.element.0) { index, element in
                    let category = element.0
                    let data = element.1
                    ForEach(data, id: \.0) { day in
                        AreaMark(x: .value("日期", day.0),
                                 y: .value("金額", day.1))
                        .interpolationMethod(.catmullRom)
                        .annotation(position: .overlay, alignment: .top) {
                            // Optional: Add tooltip on tap
                        }
                    }
                }
            }
            .frame(height: 220)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.2)))
    }
}

// MARK: - MonthlyCategoryPieChart

struct MonthlyCategoryPieChart: View {
    let entries: [ExpenseEntry]

    var categoryTotals: [(String, Int)] {
        let thisMonthEntries = entries.filter {
            Calendar.current.isDate($0.timestamp, equalTo: Date(), toGranularity: .month)
        }
        let grouped = Dictionary(grouping: thisMonthEntries, by: { $0.category })
        return grouped.map { ($0.key, $0.value.map { $0.amount }.reduce(0, +)) }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("本月分類支出")
                .font(.headline)
            Chart {
                ForEach(categoryTotals, id: \.0) { item in
                    SectorMark(angle: .value("金額", item.1))
                        .foregroundStyle(by: .value("分類", item.0))
                }
            }
            .frame(height: 220)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.2)))
    }
}

// MARK: - DailySpendingBarChart

struct DailySpendingBarChart: View {
    let entries: [ExpenseEntry]
    @State private var selectedDate: Date?

    var dailyTotals: [(Date, Int)] {
        let grouped = Dictionary(grouping: entries, by: {
            Calendar.current.startOfDay(for: $0.timestamp)
        })
        return grouped.map { ($0.key, $0.value.map { $0.amount }.reduce(0, +)) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("支出時間趨勢")
                .font(.headline)
            Chart {
                ForEach(dailyTotals, id: \.0) { item in
                    BarMark(
                        x: .value("日期", item.0),
                        y: .value("金額", item.1)
                    )
                }
                if let selected = selectedDate {
                    RuleMark(x: .value("Selected", selected))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                        .foregroundStyle(.gray)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture().onChanged { value in
                                if let date: Date = proxy.value(atX: value.location.x) {
                                    selectedDate = date
                                }
                            }
                        )
                }
            }
            .frame(height: 220)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.2)))
    }
}

// MARK: - EntryFrequencyHeatmap

struct EntryFrequencyHeatmap: View {
    let entries: [ExpenseEntry]

    var daysInMonth: Int {
        let range = Calendar.current.range(of: .day, in: .month, for: Date())!
        return range.count
    }

    var dailyMap: [Int: Int] {
        let filtered = entries.filter {
            Calendar.current.isDate($0.timestamp, equalTo: Date(), toGranularity: .month)
        }
        let grouped = Dictionary(grouping: filtered, by: {
            Calendar.current.component(.day, from: $0.timestamp)
        })
        return grouped.mapValues { $0.count }
    }

    let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 10)

    var body: some View {
        VStack(alignment: .leading) {
            Text("記帳日曆熱力圖")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(1...daysInMonth, id: \.self) { day in
                    let count = dailyMap[day] ?? 0
                    Rectangle()
                        .fill(Color.blue.opacity(min(0.2 + Double(count) * 0.1, 1.0)))
                        .aspectRatio(1, contentMode: .fit)
                        .cornerRadius(4)
                        .overlay(
                            Text("\(day)")
                                .font(.caption2)
                                .foregroundColor(.white)
                        )
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.2)))
    }
}

// MARK: - IncomeExpenseHeatmap

struct IncomeExpenseHeatmap: View {
    let entries: [ExpenseEntry]

    var body: some View {
        VStack(alignment: .leading) {
            Text("收支熱力圖（未來支援）")
                .font(.headline)
            Rectangle()
                .fill(Color.gray.opacity(0.1))
                .frame(height: 100)
                .overlay(Text("尚未實作").foregroundColor(.gray))
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.2)))
    }
}

#Preview {
    let previewEntries = (1...62).map { day in
        let month = day <= 31 ? 5 : 6
        let adjustedDay = day <= 31 ? day : day - 31
        return ExpenseEntry(
            id: UUID(),
            icon: ["🍔", "🛍️", "🎮", "💊", "🍕"].randomElement()!,
            title: ["餐飲", "娛樂", "購物", "健康", "其他"].randomElement()!,
            amount: Int.random(in: 30...300),
            category: ["飲食", "娛樂", "購物", "健康", "生活", "其他"].randomElement()!,
            timestamp: Calendar.current.date(from: DateComponents(year: 2025, month: month, day: adjustedDay, hour: Int.random(in: 6...22)))!,
            note: nil
        )
    }

    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: ExpenseEntry.self, configurations: config)

    for entry in previewEntries {
        container.mainContext.insert(entry)
    }

    return InsightsView()
        .modelContainer(container)
}
