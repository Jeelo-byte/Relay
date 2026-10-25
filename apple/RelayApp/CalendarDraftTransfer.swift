import CoreTransferable
import Foundation
import RelayKit
import UniformTypeIdentifiers

struct CalendarDraftTransfer: Transferable {
  var draft: CalendarDraft
  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: UTType(filenameExtension: "ics") ?? .data) { item in
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RelayCalendar-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appendingPathComponent(item.draft.filename)
      try Data(item.draft.content.utf8).write(to: url, options: .atomic)
      #if os(iOS)
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
      #endif
      return SentTransferredFile(url)
    }
  }
}
