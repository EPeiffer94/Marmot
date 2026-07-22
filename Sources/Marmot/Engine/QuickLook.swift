import AppKit
import Quartz

/// Quick Look for a single file — used by Duplicates so users can peek at a
/// copy before choosing which one to keep. A tiny retained data source
/// drives the shared QLPreviewPanel directly.
final class QuickLook: NSObject, QLPreviewPanelDataSource {

    static let shared = QuickLook()
    private var url: NSURL?

    static func show(path: String) {
        shared.url = NSURL(fileURLWithPath: path)
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = shared
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        url == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url
    }
}
