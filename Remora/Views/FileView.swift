import SwiftUI

struct FileContentView: View {
    let displayName: String
    let content: String?
    let isLoading: Bool
    let errorMessage: String?
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationView {
            VStack {
                if isLoading { ProgressView("Loading Content...").padding() }
                else if let errorMsg = errorMessage { Text("Error: \(errorMsg)").foregroundColor(.red).padding() }
                else if let content = content { ScrollView { Text(content).font(.system(.body, design: .monospaced)).padding().frame(maxWidth: .infinity, alignment: .leading) } }
                else { Text("No content found or file is empty.").foregroundColor(.gray).padding() }
            }
            .navigationTitle(displayName).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct DateFolderView: View {
    let dateString: String
    @State var files: [ConversationStorageService.StoredFile]
    private let storageService = ConversationStorageService()

    @State private var selectedFile: ConversationStorageService.StoredFile? = nil
    @State private var selectedFileContent: String? = nil
    @State private var detailIsLoading: Bool = false
    @State private var detailErrorMessage: String? = nil
    @State private var deleteErrorMessage: String? = nil

    var body: some View {
        VStack {
            if let errorMsg = deleteErrorMessage {
                Text("Deletion Error: \(errorMsg)")
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            if files.isEmpty {
                 Text("No files found for this date.")
                     .foregroundColor(.gray)
                     .padding()
                 Spacer()
             } else {
                 List {
                     ForEach(files) { file in
                         HStack {
                             Image(systemName: "doc.text.fill")
                                 .foregroundColor(.secondary)
                             Text(file.filename)
                             Spacer()
                         }
                         .contentShape(Rectangle())
                         .onTapGesture {
                             presentFileContent(file)
                         }
                     }
                     .onDelete(perform: deleteFileInDateFolder)
                 }
                 .listStyle(PlainListStyle())
             }
        }
        .navigationTitle(dateString)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
             ToolbarItem(placement: .navigationBarTrailing) {
                 EditButton()
                     .disabled(files.isEmpty)
             }
         }
        .sheet(item: $selectedFile) { file in
            FileContentView(
                displayName: file.filename,
                content: selectedFileContent,
                isLoading: detailIsLoading,
                errorMessage: detailErrorMessage
            )
            .onAppear {
                Task {
                    await loadFileContent(for: file)
                }
            }
        }
    }

    private func presentFileContent(_ file: ConversationStorageService.StoredFile) {
         self.selectedFile = file
         self.selectedFileContent = nil
         self.detailIsLoading = true
         self.detailErrorMessage = nil
     }

    private func loadFileContent(for file: ConversationStorageService.StoredFile) async {
         await MainActor.run {
             self.detailIsLoading = true
             self.detailErrorMessage = nil
         }
         do {
             let content = try await fetchFileContent(from: file.id)
             await MainActor.run {
                 self.selectedFileContent = content
                 self.detailIsLoading = false
             }
         } catch {
             await MainActor.run {
                 self.detailErrorMessage = "Failed to load content: \(error.localizedDescription)"
                 self.detailIsLoading = false
             }
         }
     }

     private func fetchFileContent(from url: URL) async throws -> String {
         do {
             let content = try String(contentsOf: url, encoding: .utf8)
             return content
         } catch {
             print("Error reading file content from \(url.path): \(error)")
             throw error
         }
     }

    private func deleteFileInDateFolder(at offsets: IndexSet) {
        let filesToDelete = offsets.map { files[$0] }
        files.remove(atOffsets: offsets)
        deleteErrorMessage = nil

        Task(priority: .background) {
            for file in filesToDelete {
                do {
                    try storageService.deleteStoredFile(at: file.id)
                    print("Deleted file: \(file.id.path)")
                } catch {
                    print("Error deleting file \(file.id.path): \(error)")
                    await MainActor.run {
                         self.deleteErrorMessage = "Failed to delete \(file.filename)."
                     }
                }
            }
        }
    }
}

struct FileView: View {
    private let storageService = ConversationStorageService()

    @State private var groupedFiles: [String: [ConversationStorageService.StoredFile]] = [:]
    @State private var sortedDates: [String] = []
    @State private var isLoading: Bool = false
    @State private var listErrorMessage: String? = nil

    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading Dates...")
                        .padding()
                } else if let errorMsg = listErrorMessage {
                    Text("Error: \(errorMsg)")
                        .foregroundColor(.red)
                        .padding()
                } else if sortedDates.isEmpty {
                    Text("No saved files found.")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List {
                        ForEach(sortedDates, id: \.self) { dateString in
                            NavigationLink(destination: DateFolderView(
                                dateString: dateString,
                                files: groupedFiles[dateString] ?? []
                            )) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.blue)
                                    Text(dateString)
                                    Spacer()
                                    Text("\(groupedFiles[dateString]?.count ?? 0) items")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                    .refreshable {
                        await loadFileStructure()
                    }
                }
            }
            .navigationTitle("Saved Files")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await loadFileStructure() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await loadFileStructure()
            }
        }
    }

    private func loadFileStructure() async {
        await MainActor.run {
            isLoading = true
            listErrorMessage = nil
        }
        do {
            let allFiles = try storageService.listStoredFiles()
            let grouped = Dictionary(grouping: allFiles, by: { $0.dateString })
            let dates = grouped.keys.sorted(by: >)

            await MainActor.run {
                self.groupedFiles = grouped
                self.sortedDates = dates
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.listErrorMessage = "Failed to load file structure: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
}

struct FileView_Previews: PreviewProvider {
    static var previews: some View {
        FileView()
    }
}
