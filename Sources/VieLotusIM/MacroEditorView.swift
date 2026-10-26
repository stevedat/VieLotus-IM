import SwiftUI
import VieLotusCore

/// Modern, native macOS Editor for personal shorthand / macros.
struct MacroEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [MacroEntry] = []
    @State private var searchText = ""
    @State private var newKey = ""
    @State private var newValue = ""
    @State private var editingKey: String? = nil
    @State private var showingResetAlert = false
    @FocusState private var isKeyFieldFocused: Bool

    var filteredEntries: [MacroEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return entries
        }
        return entries.filter {
            $0.key.lowercased().contains(query) || $0.value.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.indigo.gradient)
                        .frame(width: 38, height: 38)
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Bảng gõ tắt cá nhân (Macro)")
                        .font(.system(size: 15, weight: .bold))
                    Text("Gõ phím tắt rồi nhấn phím Cách hoặc Dấu câu để bung cụm từ thay thế.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            // MARK: - Add / Edit Box
            VStack(alignment: .leading, spacing: 8) {
                Text(editingKey != nil ? "CHỈNH SỬA PHÍM TẮT: \(editingKey!)" : "THÊM PHÍM TẮT MỚI")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField("Viết tắt (vd: hn)", text: $newKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                        .focused($isKeyFieldFocused)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    TextField("Cụm từ thay thế (vd: Hà Nội)", text: $newValue)
                        .textFieldStyle(.roundedBorder)

                    Button(editingKey != nil ? "Lưu" : "Thêm") {
                        saveEntry()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if editingKey != nil {
                        Button("Huỷ") {
                            cancelEditing()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))

            Divider()

            // MARK: - Search & Counter Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                TextField("Tìm kiếm phím tắt hoặc từ thay thế...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text("\(filteredEntries.count) / \(entries.count) từ")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            Divider()

            // MARK: - Macro List
            ScrollView {
                if filteredEntries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "character.book.closed")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.top, 40)
                        Text(searchText.isEmpty ? "Chưa có từ viết tắt nào." : "Không tìm thấy từ viết tắt phù hợp.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredEntries) { entry in
                            macroRow(entry)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            // MARK: - Footer Actions
            HStack(spacing: 10) {
                Button {
                    showingResetAlert = true
                } label: {
                    Label("Khôi phục mặc định", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    openMacroFile()
                } label: {
                    Label("Mở macros.json", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Đóng") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 520, height: 500)
        .alert("Khôi phục bảng gõ tắt mặc định?", isPresented: $showingResetAlert) {
            Button("Khôi phục", role: .destructive) {
                resetDefaults()
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Toàn bộ các từ gõ tắt tự thêm sẽ bị thay thế bằng danh sách mặc định của Sen Việt.")
        }
        .onAppear {
            loadEntries()
        }
        .onReceive(NotificationCenter.default.publisher(for: MacroEngine.macrosDidChangeNotification)) { _ in
            loadEntries()
        }
    }

    // MARK: - Row View
    private func macroRow(_ entry: MacroEntry) -> some View {
        HStack(spacing: 12) {
            Text(entry.key)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .frame(width: 70, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Text(entry.value)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Button {
                startEditing(entry)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Chỉnh sửa từ này")

            Button {
                deleteEntry(entry.key)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Xoá từ này")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(editingKey == entry.key ? Color.indigo.opacity(0.1) : Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }

    // MARK: - Actions
    private func loadEntries() {
        entries = MacroEngine.shared.getMacroEntries()
    }

    private func saveEntry() {
        let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let val = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !val.isEmpty else { return }

        // If key was edited/renamed from an old key, remove the old key first
        if let oldKey = editingKey, oldKey != key {
            MacroEngine.shared.removeMacro(key: oldKey)
        }

        MacroEngine.shared.setMacro(key: key, value: val)
        cancelEditing()
        loadEntries()
    }

    private func startEditing(_ entry: MacroEntry) {
        editingKey = entry.key
        newKey = entry.key
        newValue = entry.value
        isKeyFieldFocused = true
    }

    private func cancelEditing() {
        editingKey = nil
        newKey = ""
        newValue = ""
    }

    private func deleteEntry(_ key: String) {
        if editingKey == key {
            cancelEditing()
        }
        MacroEngine.shared.removeMacro(key: key)
        loadEntries()
    }

    private func resetDefaults() {
        cancelEditing()
        MacroEngine.shared.resetToDefaults()
        loadEntries()
    }

    private func openMacroFile() {
        if let url = MacroEngine.defaultStorageURL {
            if !FileManager.default.fileExists(atPath: url.path) {
                try? MacroEngine.shared.saveToDisk(url: url)
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
