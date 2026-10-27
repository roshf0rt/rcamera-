import AVKit
import CameraCore
import SwiftUI

enum ThumbnailCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func load(url: URL, version: String) async -> UIImage? {
        let key = "\(url.path)|\(version)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = await Task.detached(priority: .utility) { UIImage(contentsOfFile: url.path) }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

struct CaptureThumbnail: View {
    @Environment(AppModel.self) private var model
    let record: CaptureRecord
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(white: 0.12)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .task(id: "\(record.id)-\(record.presetID)-\(record.evPushPull)") {
            image = await ThumbnailCache.load(
                url: model.url(.thumbnail, for: record),
                version: "\(record.presetID)-\(record.evPushPull)"
            )
        }
    }
}

struct GalleryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        NavigationStack {
            Group {
                if model.captures.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 38))
                        Text("No captures yet").font(.headline)
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(model.captures) { record in
                                Button { selection = record.id } label: {
                                    Color.clear
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay { CaptureThumbnail(record: record) }
                                        .overlay(alignment: .bottomLeading) { badges(for: record) }
                                        .clipped()
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .background(Color.black)
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                }
            }
            .navigationDestination(item: $selection) { id in
                CaptureDetailView(recordID: id) { selection = $0 }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func badges(for record: CaptureRecord) -> some View {
        HStack(spacing: 4) {
            if record.kind == .video { Image(systemName: "video.fill") }
            if record.isFavorite { Image(systemName: "heart.fill") }
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .shadow(radius: 2)
        .padding(6)
    }
}

struct CaptureDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let recordID: UUID
    /// Opens another capture in place, for swiping sideways through the library.
    var open: (UUID) -> Void = { _ in }

    @State private var showRedevelop = false
    @State private var confirmDelete = false
    @State private var image: UIImage?
    @State private var player: AVPlayer?

    private var record: CaptureRecord? { model.captures.first { $0.id == recordID } }

    var body: some View {
        Group {
            if let record {
                content(record)
            } else {
                Color.black.onAppear { dismiss() }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Swipe down goes back to the grid, swipe left and right move to the neighbouring capture.
    private func swipe(_ value: DragGesture.Value, _ record: CaptureRecord) {
        let dx = value.translation.width, dy = value.translation.height
        if dy > 90, dy > abs(dx) * 1.4 {
            dismiss()
        } else if abs(dx) > 70, abs(dx) > abs(dy) * 1.4 {
            // The library is newest first: a swipe left goes to an older capture.
            let all = model.captures
            guard let index = all.firstIndex(where: { $0.id == record.id }) else { return }
            let target = dx < 0 ? index + 1 : index - 1
            if all.indices.contains(target) { open(all[target].id) }
        }
    }

    private func content(_ record: CaptureRecord) -> some View {
        VStack(spacing: 0) {
            header(record)
            HStack {
                Text(badge(for: record))
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.chrome))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Spacer(minLength: 0)
            media(record)
            Spacer(minLength: 0)
            bottomBar(record)
        }
        .task(id: "\(record.id)-\(record.presetID)-\(record.evPushPull)") {
            if record.kind == .video {
                player = AVPlayer(url: model.url(.video, for: record))
            } else {
                let url = model.url(.processed, for: record)
                image = await Task.detached { UIImage(contentsOfFile: url.path) }.value
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { swipe($0, record) })
        .fullScreenCover(isPresented: $showRedevelop) { RedevelopView(recordID: record.id) }
        .confirmationDialog("Delete this capture?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.delete(record)
                dismiss()
            }
        }
    }

    private func header(_ record: CaptureRecord) -> some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "arrow.left").font(.system(size: 22, weight: .medium)).frame(width: 44, height: 44)
            }
            Spacer()
            VStack(spacing: 2) {
                if let place = record.placeName {
                    Text(place).foregroundStyle(Theme.secondaryText)
                }
                Text(Self.dateText(record.date)).foregroundStyle(Theme.secondaryText)
            }
            .font(.system(size: 14, design: .monospaced))
            Spacer()
            ShareLink(item: model.url(record.kind == .video ? .video : .processed, for: record)) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 22)).frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func media(_ record: CaptureRecord) -> some View {
        if record.kind == .video {
            if let player {
                VideoPlayer(player: player).aspectRatio(9.0 / 16.0, contentMode: .fit)
            } else {
                ProgressView()
            }
        } else if let image {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            ProgressView()
        }
    }

    private func bottomBar(_ record: CaptureRecord) -> some View {
        HStack {
            Button { model.toggleFavorite(record) } label: {
                Image(systemName: record.isFavorite ? "heart.fill" : "heart").font(.system(size: 26)).frame(width: 52, height: 52)
            }
            .foregroundStyle(record.isFavorite ? Theme.accent : .white)
            Spacer()
            if model.canRedevelop(record) {
                Button { showRedevelop = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.stack.3d.up.fill")
                        Text("Redevelop").font(.system(size: 20, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .frame(height: 56)
                    .background(Capsule().fill(Theme.chrome))
                }
            }
            Spacer()
            Button { confirmDelete = true } label: {
                Image(systemName: "trash").font(.system(size: 24)).frame(width: 52, height: 52)
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func badge(for record: CaptureRecord) -> String {
        if record.kind == .video { return "VIDEO" }
        return record.hasRAW ? "RAW + HEIC" : "HEIC"
    }

    static func dateText(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "Today, \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday, \(time)" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
