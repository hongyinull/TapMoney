//
//  ContentView.swift
//  TapMoney
//
//  Created by HONGYINULL on 2025/5/22.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Model

@Model
class ExpenseEntry: Identifiable {
    var id: UUID
    var icon: String
    var title: String
    var amount: Int
    var category: String
    var timestamp: Date
    var note: String?

    init(id: UUID = UUID(), icon: String, title: String, amount: Int, category: String, timestamp: Date, note: String? = nil) {
        self.id = id
        self.icon = icon
        self.title = title
        self.amount = amount
        self.category = category
        self.timestamp = timestamp
        self.note = note
    }
}

// MARK: - DTO

struct ExpenseDTO: Codable {
    let icon: String
    let title: String
    let amount: Int
    let category: String
    let timestamp: String
    let note: String?

    func toModel() -> ExpenseEntry {
        ExpenseEntry(icon: icon, title: title, amount: amount, category: category, timestamp: preciseFormatter.date(from: timestamp) ?? Date(), note: note)
    }
}

// MARK: - ViewModel

@Observable
class ExpenseViewModel {
    var prompt: String = ""
    var isLoading: Bool = false
    var errorMessage: String?

    func submit(with modelContext: ModelContext) {
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let result = try await APIService.sendPrompt(prompt)
                if result.isEmpty {
                    self.errorMessage = "AI 回傳資料格式錯誤，請檢查語句或稍後再試。"
                }
                for entry in result {
                    modelContext.insert(entry)
                }
            } catch {
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .dataCorrupted(let context):
                        errorMessage = "資料錯誤：\(context.debugDescription)"
                    case .keyNotFound(let key, let context):
                        errorMessage = "缺少欄位：\(key.stringValue) - \(context.debugDescription)"
                    case .typeMismatch(let type, let context):
                        errorMessage = "類型錯誤：\(type) - \(context.debugDescription)"
                    case .valueNotFound(let type, let context):
                        errorMessage = "值遺失：\(type) - \(context.debugDescription)"
                    @unknown default:
                        errorMessage = "未知解碼錯誤"
                    }
                } else {
                    errorMessage = "發生錯誤：\(error.localizedDescription)"
                }

                if let requestData = try? JSONEncoder().encode(["prompt": prompt]),
                   let (data, _) = try? await URLSession.shared.data(for: {
                       var req = URLRequest(url: APIService.endpoint)
                       req.httpMethod = "POST"
                       req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                       req.httpBody = requestData
                       return req
                   }()),
                   let raw = String(data: data, encoding: .utf8) {
                    print("⚠️ GPT 回傳內容：\n\(raw)")
                }
            }
            isLoading = false
        }
    }
}

// MARK: - API Service

struct APIService {
    static let endpoint = URL(string: "https://openai-proxy.yinull-cloud.workers.dev")!

    static func sendPrompt(_ prompt: String) async throws -> [ExpenseEntry] {
        let body = ["prompt": prompt]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(ResponseWrapper.self, from: data)
        let entries = decoded.data?.map { $0.toModel() } ?? []

        if entries.isEmpty {
            print("⚠️ GPT 回傳內容（未能解碼）：\n\(decoded.raw ?? "無 raw 資料")")
        }

        return entries
    }

    struct ResponseWrapper: Codable {
        let data: [ExpenseDTO]?
        let raw: String?
    }
}

// MARK: - Formatters

let preciseFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd'T'HH:mmXXXXX"
    f.timeZone = TimeZone(identifier: "Asia/Taipei")
    return f
}()

let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withTimeZone]
    f.timeZone = TimeZone(identifier: "Asia/Taipei")
    return f
}()

let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    f.timeZone = TimeZone(identifier: "Asia/Taipei")
    return f
}()

let displayDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .full
    f.timeZone = TimeZone(identifier: "Asia/Taipei")
    return f
}()

// MARK: - Row View

struct EntryRow: View {
    let entry: ExpenseEntry
    let isSelecting: Bool
    let isSelected: Bool
    var namespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                // Removed left-side selection icon
                Text(entry.icon)
                    .font(.title2)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.headline)
                    Text(entry.category)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text(timeFormatter.string(from: entry.timestamp))
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("$\(entry.amount)")
                        .font(.headline)
                        .bold()
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelecting && isSelected ? Color.accentColor.opacity(0.2) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor, lineWidth: isSelecting && isSelected ? 2 : 0)
        )
        .offset(y: isSelecting && isSelected ? -5 : 0)
        .scaleEffect(isSelecting && isSelected ? 1.02 : 1.0)
        .matchedGeometryEffect(id: entry.id, in: namespace)
    }
}

// MARK: - EditableEntryForm View

struct EditableEntryForm: View {
    @Bindable var entry: ExpenseEntry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section(header: Text("Emoji")) {
                TextField("emoji", text: $entry.icon)
                    .submitLabel(.done)
                    .keyboardType(.default)
                    .textInputAutocapitalization(.never)
            }
            Section(header: Text("標題")) {
                TextField("標題", text: $entry.title)
                    .submitLabel(.done)
            }
            Section(header: Text("分類")) {
                TextField("分類", text: $entry.category)
                    .submitLabel(.done)
            }
            Section(header: Text("金額")) {
                TextField("金額", value: $entry.amount, format: .number)
                    .keyboardType(.numberPad)
                    .submitLabel(.done)
            }
            Section(header: Text("時間")) {
                DatePicker("時間", selection: $entry.timestamp, displayedComponents: [.date, .hourAndMinute])
            }
            Section(header: Text("備註")) {
                TextField("備註", text: Binding<String>(
                    get: { entry.note ?? "" },
                    set: { entry.note = $0 }
                ))
                .submitLabel(.done)
            }

            Section {
                Button(role: .destructive) {
                    modelContext.delete(entry)
                    dismiss()
                } label: {
                    Label("刪除這筆紀錄", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Detail View

struct DetailView: View {
    @Bindable var entry: ExpenseEntry

    var body: some View {
        EditableEntryForm(entry: entry)
            .navigationTitle(entry.title)
    }
}

// 擴充 Binding 以支援 Optional 綁定時預設為空字串
extension Binding where Value == String? {
    init(_ source: Binding<String?>, replacingNilWith defaultValue: String) {
        self.init(
            get: { source.wrappedValue ?? defaultValue },
            set: { newValue in source.wrappedValue = newValue }
        )
    }
}

// MARK: - ContentView with TabView

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MainContentView()
                .tabItem {
                    Label("記帳", systemImage: "list.bullet.rectangle")
                }
                .tag(0)

            InsightsView()
                .tabItem {
                    Label("趨勢", systemImage: "chart.bar")
                }
                .tag(1)
        }
    }
}

// 原本 ContentView 主體內容移至此
struct MainContentView: View {
    @State private var vm = ExpenseViewModel()
    @Query(sort: \ExpenseEntry.timestamp, order: .reverse) var entries: [ExpenseEntry]
    @Environment(\.modelContext) private var modelContext

    @State private var isSelecting: Bool = false
    @State private var selectedEntries: Set<UUID> = []
    // 語音輸入狀態相關變數
    @State private var isRecording = false
    @State private var speechRecognizer = StableSpeechRecognizer()

    @Namespace private var namespace

    func dateHeaderString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        return formatter.string(from: date)
    }

    // 分組並排序，依據 timestamp 分天顯示
    var groupedEntries: [(date: Date, entries: [ExpenseEntry])] {
        let grouped = Dictionary(grouping: entries) { entry in
            Calendar.current.startOfDay(for: entry.timestamp)
        }
        return grouped.sorted { $0.key > $1.key }.map { (date: $0.key, entries: $0.value) }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // 自定義 Header
                HStack {
                    Text("點點錢包")
                        .font(.title.bold())

                    Spacer()

                    Text("beta \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15)))
                        .foregroundColor(.accentColor)
                }
                .padding(.horizontal)

                HStack {
                    TextField("輸入記帳語句…", text: $vm.prompt)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(isSelecting)
                        .submitLabel(.send)
                        .onSubmit {
                            vm.submit(with: modelContext)
                            vm.prompt = ""
                        }
                    // 語音輸入按鈕
                    ZStack {
                        Image(systemName: isRecording ? "mic.fill" : "mic")
                            .scaleEffect(isRecording ? 2.0 : 1.0)
                            .foregroundColor(.accentColor)
                            .animation(.interpolatingSpring(stiffness: 240, damping: 20), value: isRecording)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !isRecording {
                                    isRecording = true
                                    speechRecognizer.start { text in
                                        vm.prompt = text
                                    }
                                }
                            }
                            .onEnded { _ in
                                if isRecording {
                                    isRecording = false
                                    speechRecognizer.stop()
                                }
                                // 不自動送出或清空 prompt
                            }
                    )
                    Button(action: {
                        vm.submit(with: modelContext)
                        vm.prompt = ""
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.accentColor)
                    }
                    .disabled(vm.isLoading || isSelecting || vm.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)

                if vm.isLoading {
                    ProgressView("處理中…")
                }

                if let error = vm.errorMessage {
                    Text(error).foregroundColor(.red)
                }

                // --- LazyVStack with date headers (entries sorted by timestamp desc, grouped by date) ---
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(groupedEntries, id: \.date) { date, entries in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(dateHeaderString(for: date))
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .padding(.horizontal)

                                ForEach(entries) { entry in
                                    Group {
                                        if isSelecting {
                                            EntryRow(entry: entry, isSelecting: true, isSelected: selectedEntries.contains(entry.id), namespace: namespace)
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    withAnimation(.interpolatingSpring(stiffness: 240, damping: 22)) {
                                                        if selectedEntries.contains(entry.id) {
                                                            selectedEntries.remove(entry.id)
                                                        } else {
                                                            selectedEntries.insert(entry.id)
                                                        }
                                                    }
                                                }
                                                .onLongPressGesture {
                                                    // No action needed on long press in selecting mode
                                                }
                                        } else {
                                            NavigationLink(destination: DetailView(entry: entry)) {
                                                EntryRow(entry: entry, isSelecting: false, isSelected: false, namespace: namespace)
                                            }
                                            .simultaneousGesture(
                                                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                                    withAnimation(.interpolatingSpring(stiffness: 240, damping: 22)) {
                                                        isSelecting = true
                                                    }
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                                        withAnimation(.interpolatingSpring(stiffness: 240, damping: 22)) {
                                                            selectedEntries = [entry.id]
                                                        }
                                                    }
                                                }
                                            )
                                        }
                                    }
                                    .padding(.horizontal)
                                    .opacity(isSelecting && !selectedEntries.contains(entry.id) ? 0.5 : 1.0)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - StableSpeechRecognizer

import Speech

class StableSpeechRecognizer: ObservableObject {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func start(onText: @escaping (String) -> Void) {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            print("🚫 語音辨識權限未開啟")
            return
        }

        stop()

        do {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            recognitionTask = recognizer?.recognitionTask(with: request) { result, error in
                if let result = result {
                    DispatchQueue.main.async {
                        onText(result.bestTranscription.formattedString)
                    }
                } else if let error = error {
                    print("❗ 辨識錯誤：\(error.localizedDescription)")
                }
            }

        } catch {
            print("❗ 語音啟動失敗：\(error.localizedDescription)")
        }
    }

    func stop() {
        recognitionTask?.cancel()
        recognitionTask = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }
}

// MARK: - ExportService

class ExportService {
    static let shared = ExportService()

    func exportPlainText(entries: [ExpenseEntry]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd HHmm"
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        
        return entries.map { entry in
            let timeStr = formatter.string(from: entry.timestamp)
            return "\(entry.icon)\(entry.title)｜\(entry.category)｜$\(entry.amount)｜\(timeStr)"
        }.joined(separator: "\n")
    }

    func exportCSV(entries: [ExpenseEntry]) -> String {
        var rows: [String] = ["icon,title,amount,category,timestamp,note"]
        for entry in entries {
            let timestamp = preciseFormatter.string(from: entry.timestamp)
            let note = entry.note?.replacingOccurrences(of: ",", with: ";") ?? ""
            rows.append("\"\(entry.icon)\",\"\(entry.title)\",\(entry.amount),\"\(entry.category)\",\"\(timestamp)\",\"\(note)\"")
        }
        return rows.joined(separator: "\n")
    }
}

// MARK: - ShareService

class ShareService {
    static let shared = ShareService()

    func shareText(_ text: String) {
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController?.present(activityVC, animated: true, completion: nil)
    }

    func shareFile(content: String, fileName: String) {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? content.write(to: tmpURL, atomically: true, encoding: .utf8)
        let activityVC = UIActivityViewController(activityItems: [tmpURL], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController?.present(activityVC, animated: true, completion: nil)
    }
}

// MARK: - Preview

 #Preview {
    let previewContainer: ModelContainer = {
        let schema = Schema([ExpenseEntry.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    let context = previewContainer.mainContext
    // 2025-05-22
    context.insert(ExpenseEntry(
        icon: "🍔",
        title: "漢堡",
        amount: 120,
        category: "飲食",
        timestamp: preciseFormatter.date(from: "2025-05-22T23:00+08:00") ?? Date(),
        note: "午餐外帶"
    ))
    // 2025-05-21
    context.insert(ExpenseEntry(
        icon: "🍱",
        title: "便當",
        amount: 95,
        category: "飲食",
        timestamp: preciseFormatter.date(from: "2025-05-21T12:30+08:00") ?? Date(),
        note: "昨天午餐"
    ))
    // 2025-05-20
    context.insert(ExpenseEntry(
        icon: "🧋",
        title: "珍奶",
        amount: 50,
        category: "飲食",
        timestamp: preciseFormatter.date(from: "2025-05-20T15:10+08:00") ?? Date(),
        note: "小確幸"
    ))

    return ContentView()
        .modelContainer(previewContainer)
        .tint(.orange)
}
