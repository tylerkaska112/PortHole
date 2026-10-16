// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The system file picker, from UIKit — the same fix HomeControl, CC2 Slicer and SafelyRouted use. SwiftUI's `fileImporter` is
/// unreliable here: inside a list it can ignore taps, it greys out file types iOS doesn't know (.mobileprovision), and it fails in
/// re-signed builds (which this app always is). Any file can be chosen, and the app is handed private copies, so no
/// security-scoped access is needed. Present it in a `.sheet`. Don't use `.fileImporter` anywhere in this app.
struct FilePickerSheet: UIViewControllerRepresentable {
    var allowsMultiple = false
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = allowsMultiple
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if urls.isEmpty { onCancel() } else { onPick(urls) }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onCancel() }
    }
}

extension URL {
    /// The picker accepts any file, so callers check what they were given.
    func hasExtension(_ allowed: String...) -> Bool { allowed.contains(pathExtension.lowercased()) }
}

/// The system picker for a FOLDER (a game's install folder). Unlike `FilePickerSheet` this cannot hand over a copy: the app gets
/// security-scoped access to the folder and copies it itself (`GameImporter`). Present it in a `.sheet`; not `.fileImporter`.
struct FolderPickerSheet: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void
        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) { self.onPick = onPick; self.onCancel = onCancel }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let u = urls.first { onPick(u) } else { onCancel() }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onCancel() }
    }
}
