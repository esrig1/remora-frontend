import Foundation

class ConversationStorageService {

    // MARK: - Data Structures (Existing)

    struct Conversation: Codable {
        var entries: [Entry]

        struct Entry: Codable {
            var speaker: String
            var text: String
        }
    }

    enum FileUrlType: String {
        case conversation = "conversation.txt"
        case summary = "summary.txt"
    }

    /// Errors related to storage operations
    enum StorageError: Error, LocalizedError {
        case directoryCreationFailed(Error)
        case fileWriteFailed(Error)
        case fileReadFailed(Error)
        case fileDeleteFailed(Error)
        case directoryListingFailed(Error)
        case directoryNotFound(String)
        case fileNotFound(URL)

        // Add descriptions if needed
         var errorDescription: String? {
             switch self {
                 // ... add descriptions for other cases ...
             case .fileWriteFailed(let error): return "Failed to write to file: \(error.localizedDescription)"
             default: return "\(self)" // Basic description
             }
         }
    }


    // MARK: - Properties (Existing)

    private var fileManager = FileManager.default

    // MARK: - Initialization (Existing)

    init() {
        print("ConversationStorageService initialized.")
    }

    // MARK: - Private Helpers (Existing)

    // Note: This operates on the *directory containing* the URL.
    private func createDirectoryIfNeeded(at url: URL) {
        let directoryURL = url.deletingLastPathComponent()
         guard !fileManager.fileExists(atPath: directoryURL.path) else { return }
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            print("Created directory implicitly: \(directoryURL.path)")
        } catch {
            print("Error creating directory \(directoryURL.path): \(error)")
        }
    }

    // MARK: - Modified File Writing Function

    /// Appends the given string (followed by a newline) to the specified file type for the current date.
    func addConversationToFile(conversationText: String, for type: FileUrlType) {
         let url = getFileUrl(for: type) // Get the URL for today and the type

         // Ensure the directory exists before trying to get a file handle.
         // getFileUrl should handle this, but this adds safety.
         createDirectoryIfNeeded(at: url)

         do {
             // Ensure the file exists before opening for append; create if not.
             if !fileManager.fileExists(atPath: url.path) {
                 fileManager.createFile(atPath: url.path, contents: nil, attributes: nil)
                 print("Created empty file at: \(url.path)")
             }

             // Open the file for appending.
             let fileHandle = try FileHandle(forWritingTo: url)

             // Move to the end of the file to append data.
             try fileHandle.seekToEnd()

             // Prepare the string data (append a newline for separation).
             let lineToAppend = conversationText + "\n"
             if let data = lineToAppend.data(using: .utf8) {
                 // Write the data to the file.
                 fileHandle.write(data)
             } else {
                 // Handle the rare case where string encoding fails.
                 print("Warning: Could not encode conversation text to UTF-8 data.")
             }

             // Close the file handle.
             try fileHandle.close()
             print("Appended text to \(url.path)")

         } catch {
             // Handle errors during file operations.
             print("Error appending conversation text to file \(url.path): \(StorageError.fileWriteFailed(error).localizedDescription)")
             // Depending on requirements, you might want to re-throw the specific error:
             // throw StorageError.fileWriteFailed(error)
         }
     }


    // MARK: - URL Generation (Existing)

    func getFileUrl(for type: FileUrlType) -> URL {
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Could not access user's Documents directory.")
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateFolderName = formatter.string(from: Date())

        let recordingsDirectory = documentsPath
            .appendingPathComponent("Conversations")
            .appendingPathComponent(dateFolderName)

        // Ensure the directory exists (handles intermediate directories)
        if !fileManager.fileExists(atPath: recordingsDirectory.path) {
            do {
                try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
                print("Created directory via getFileUrl: \(recordingsDirectory.path)")
            } catch {
                print("Failed to create directory \(recordingsDirectory.path): \(error.localizedDescription)")
            }
        }

        return recordingsDirectory.appendingPathComponent(type.rawValue)
    }

    // MARK: - File Listing (Assumed Added Previously) - If not present, add these back

    struct StoredFile: Identifiable, Hashable { // Add this struct if missing
        let id: URL
        let dateString: String
        let filename: String
        var displayName: String { "\(dateString) / \(filename)" }
    }

     func listStoredFiles() throws -> [StoredFile] {
         // ... (Implementation from previous step) ...
         var discoveredFiles: [StoredFile] = []
         guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
              throw StorageError.directoryNotFound("Documents")
         }
         let conversationsBaseDir = documentsPath.appendingPathComponent("Conversations")
         guard fileManager.fileExists(atPath: conversationsBaseDir.path) else { return [] }
         let dateFolderURLs = try fileManager.contentsOfDirectory(at: conversationsBaseDir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
         for dateFolderURL in dateFolderURLs {
              var isDir: ObjCBool = false
              guard fileManager.fileExists(atPath: dateFolderURL.path, isDirectory: &isDir), isDir.boolValue else { continue }
              let dateString = dateFolderURL.lastPathComponent
              let fileURLs = try fileManager.contentsOfDirectory(at: dateFolderURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
              for fileURL in fileURLs {
                  if fileURL.pathExtension == "txt" {
                      discoveredFiles.append(StoredFile(id: fileURL, dateString: dateString, filename: fileURL.lastPathComponent))
                  }
              }
         }
         discoveredFiles.sort { ($0.dateString, $0.filename) > ($1.dateString, $1.filename) } // Simple sort
         return discoveredFiles
     }

    // MARK: - File Deletion (Assumed Added Previously) - If not present, add this back

     func deleteStoredFile(at url: URL) throws {
         // ... (Implementation from previous step, including cleanup) ...
         guard fileManager.fileExists(atPath: url.path) else { throw StorageError.fileNotFound(url) }
         do {
             try fileManager.removeItem(at: url)
             cleanUpEmptyDirectory(at: url.deletingLastPathComponent()) // Call cleanup
         } catch {
             throw StorageError.fileDeleteFailed(error)
         }
     }

     // MARK: - Optional Cleanup Helper (Assumed Added Previously) - If not present, add this back

     private func cleanUpEmptyDirectory(at directoryURL: URL) {
        // ... (Implementation from previous step) ...
         do {
             let contents = try fileManager.contentsOfDirectory(atPath: directoryURL.path)
             if contents.isEmpty {
                 try fileManager.removeItem(at: directoryURL)
                 let parentDirectory = directoryURL.deletingLastPathComponent()
                 if parentDirectory.lastPathComponent == "Conversations" { cleanUpEmptyDirectory(at: parentDirectory) }
             }
         } catch let error as NSError where error.code == NSFileReadNoSuchFileError { // Already gone
         } catch { print("Could not check/remove empty dir \(directoryURL.path): \(error)") }
     }
}
