import SwiftUI

struct FileShelfView: View {
    @ObservedObject var model: FileShelfViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: NotchGeometry.detailContentGap) {
            DetailHeading {
                Image(systemName: "tray")
            } title: { Text("File Shelf") } accessory: {
                if !model.selectedIDs.isEmpty {
                    Text("\(model.selectedIDs.count) selected").font(AppFont.subtitle).foregroundStyle(.secondary)
                }
                NotchIconButton(symbol: "doc.on.doc", label: "Copy selected files") { model.copySelection() }
                    .disabled(model.selectedIDs.isEmpty)
                NotchIconButton(symbol: "doc.on.clipboard", label: "Paste files into shelf") { model.paste() }
                NotchIconButton(symbol: "trash", label: "Clear File Shelf", hint: "Clear the shelf without deleting the original files") { model.clear() }
                    .disabled(model.items.isEmpty)
            }
            .buttonStyle(NotchButtonStyle(.plain))
            FileShelfCollection(model: model)
                .frame(minHeight: 84, maxHeight: .infinity)
                .overlay {
                    if model.items.isEmpty {
                        Text("No files").font(AppFont.title).foregroundStyle(.secondary).allowsHitTesting(false)
                    }
                }
        }
    }
}

private struct FileShelfCollection: NSViewControllerRepresentable {
    let model: FileShelfViewModel
    func makeNSViewController(context: Context) -> FileShelfContentController { FileShelfContentController(model: model) }
    func updateNSViewController(_ controller: FileShelfContentController, context: Context) {}
}
