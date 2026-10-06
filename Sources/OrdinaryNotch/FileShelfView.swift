import SwiftUI

struct FileShelfView: View {
    @ObservedObject var model: FileShelfViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("File Shelf", systemImage: "tray").font(AppFont.label)
                Spacer()
                if !model.items.isEmpty { Button("Clear") { model.clear() }.help("Remove all files from the shelf") }
            }
            .buttonStyle(.borderless).font(AppFont.subtitle)
            if model.items.isEmpty {
                VStack(spacing: 5) {
                    Text("Drop files here").font(AppFont.title)
                    Text("Keep them handy, then drag them into another app.")
                        .font(AppFont.subtitle).foregroundStyle(.white.opacity(0.65))
                    Text("The shelf clears when you quit.")
                        .font(AppFont.subtitle).foregroundStyle(.white.opacity(0.65))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(model.items) { item in
                            Button { model.open(item) } label: {
                                VStack(spacing: 5) {
                                    Group {
                                        if let thumbnail = item.thumbnail {
                                            Image(nsImage: thumbnail).resizable().scaledToFit()
                                                .frame(width: 64, height: 44)
                                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                        } else {
                                            Image(nsImage: item.icon).resizable().scaledToFit().frame(width: 34, height: 34)
                                        }
                                    }.frame(width: 64, height: 44).accessibilityHidden(true)
                                    Text(item.url.lastPathComponent).font(AppFont.subtitle)
                                        .lineLimit(2).truncationMode(.middle).multilineTextAlignment(.center)
                                }.frame(width: 88, height: 76)
                            }
                            .buttonStyle(NotchHoverButtonStyle())
                            .help(item.url.path)
                            .accessibilityLabel(item.url.lastPathComponent)
                            .onDrag { NSItemProvider(object: item.url as NSURL) }
                            .contextMenu {
                                Button("Open") { model.open(item) }
                                Button("Show in Finder") { model.reveal(item) }
                                Button("Remove from Shelf") { model.remove(item) }
                            }
                            .accessibilityAction(named: "Remove from Shelf") { model.remove(item) }
                        }
                    }
                }
            }
            if let error = model.error {
                Text(error).font(AppFont.subtitle).foregroundStyle(.orange).lineLimit(2)
            }
        }
    }
}
