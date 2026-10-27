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
    /// The capture waiting for the delete confirmation, set from the long-press menu.
    @State private var pendingDelete: CaptureRecord?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        ZStack {
            library
            if let id = selection {
                CaptureViewer(startID: id) {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) { selection = nil }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.94)),
                    removal: .opacity
                ))
                .zIndex(1)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var library: some View {
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
                                Button {
                                    withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { selection = record.id }
                                } label: {
                                    Color.clear
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay { CaptureThumbnail(record: record) }
                                        .overlay(alignment: .bottomLeading) { badges(for: record) }
                                        .clipped()
                                }
                                .buttonStyle(PressableStyle(scale: 0.96))
                                .contextMenu {
                                    Button { model.toggleFavorite(record) } label: {
                                        Label(record.isFavorite ? "Unfavorite" : "Favorite", systemImage: record.isFavorite ? "heart.slash" : "heart")
                                    }
                                    ShareLink(item: model.url(record.kind == .video ? .video : .processed, for: record)) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    Button(role: .destructive) { pendingDelete = record } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .background(Color.black)
            .confirmationDialog(
                "Delete this capture?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let record = pendingDelete { model.delete(record) }
                    pendingDelete = nil
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                }
            }
        }
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

/// The full-screen viewer over the library. Captures page sideways; dragging down shrinks the photo and
/// fades the black behind it, and letting go past the threshold closes the viewer, like Photos.
struct CaptureViewer: View {
    @Environment(AppModel.self) private var model
    let startID: UUID
    let close: () -> Void

    @State private var current: UUID?
    @State private var dragY: CGFloat = 0
    /// Decided once per drag: true for a downward drag that should close, false for anything else.
    @State private var closingDrag: Bool?
    @State private var zoomed = false
    @State private var showRedevelop = false
    @State private var confirmDelete = false

    private var record: CaptureRecord? { model.captures.first { $0.id == (current ?? startID) } }

    var body: some View {
        let progress: CGFloat = min(max(dragY / 320, 0), 1)
        let chromeOpacity: Double = 1 - min(1, Double(progress) * 2.5)
        ZStack {
            Color.black.opacity(Double(1 - progress)).ignoresSafeArea()

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(model.captures) { item in
                        CapturePage(
                            record: item,
                            isCurrent: item.id == (current ?? startID),
                            zoomed: $zoomed,
                            askDelete: { confirmDelete = true }
                        )
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $current)
            .scrollIndicators(.hidden)
            .scrollDisabled(zoomed || dragY > 0)
            .ignoresSafeArea()
            .offset(y: dragY)
            .scaleEffect(1 - 0.25 * progress)
            .simultaneousGesture(dismissDrag)

            if let record {
                chrome(record)
                    .opacity(chromeOpacity)
            }
        }
        .onAppear { current = startID }
        .onChange(of: model.captures.map(\.id)) { _, ids in
            if ids.isEmpty { close() }
        }
        .sensoryFeedback(.selection, trigger: current)
        .fullScreenCover(isPresented: $showRedevelop) {
            if let record { RedevelopView(recordID: record.id) }
        }
        .confirmationDialog("Delete this capture?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteCurrent() }
        }
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !zoomed else { return }
                if closingDrag == nil {
                    let dx = value.translation.width, dy = value.translation.height
                    closingDrag = dy > 0 && dy > abs(dx) * 1.2
                }
                guard closingDrag == true else { return }
                dragY = max(0, value.translation.height)
            }
            .onEnded { value in
                defer { closingDrag = nil }
                guard closingDrag == true else { return }
                if value.translation.height > 110 || value.predictedEndTranslation.height > 420 {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    close()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { dragY = 0 }
                }
            }
    }

    /// Deletes the shown capture and moves to its neighbour, or closes when it was the last one.
    private func deleteCurrent() {
        guard let record else { return }
        let all = model.captures
        let index = all.firstIndex { $0.id == record.id } ?? 0
        let neighbour = all.indices.contains(index + 1) ? all[index + 1].id : (index > 0 ? all[index - 1].id : nil)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            model.delete(record)
            current = neighbour
        }
        if neighbour == nil { close() }
    }

    private func chrome(_ record: CaptureRecord) -> some View {
        VStack(spacing: 0) {
            header(record)
            HStack {
                Text(badge(for: record))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.45)).background(.ultraThinMaterial, in: Capsule()))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            Spacer(minLength: 0)
            bottomBar(record)
        }
    }

    private func header(_ record: CaptureRecord) -> some View {
        HStack {
            Button(action: close) {
                Image(systemName: "chevron.down").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
            }
            .buttonStyle(PressableStyle())
            Spacer()
            VStack(spacing: 2) {
                if let place = record.placeName {
                    Text(place)
                }
                Text(Self.dateText(record.date))
            }
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(.white.opacity(0.75))
            Spacer()
            ShareLink(item: model.url(record.kind == .video ? .video : .processed, for: record)) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 20)).frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .background(LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private func bottomBar(_ record: CaptureRecord) -> some View {
        HStack {
            Button { model.toggleFavorite(record) } label: {
                Image(systemName: record.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 24))
                    .frame(width: 52, height: 52)
                    .contentTransition(.symbolEffect(.replace))
            }
            .foregroundStyle(record.isFavorite ? Theme.accent : .white)
            .buttonStyle(PressableStyle())
            .sensoryFeedback(.impact(weight: .light), trigger: record.isFavorite)
            Spacer()
            if model.canRedevelop(record) {
                Button { showRedevelop = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.stack.3d.up.fill")
                        Text("Redevelop").font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(height: 52)
                    .background(Capsule().fill(Color.black.opacity(0.45)).background(.ultraThinMaterial, in: Capsule()))
                }
                .buttonStyle(PressableStyle())
            }
            Spacer()
            Button { confirmDelete = true } label: {
                Image(systemName: "trash").font(.system(size: 22)).frame(width: 52, height: 52)
            }
            .foregroundStyle(.white)
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
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

/// One capture in the viewer. The photo loads when the page comes near; video plays only on the shown page.
private struct CapturePage: View {
    @Environment(AppModel.self) private var model
    let record: CaptureRecord
    let isCurrent: Bool
    @Binding var zoomed: Bool
    let askDelete: () -> Void

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var localZoom = false

    var body: some View {
        ZStack {
            if record.kind == .video {
                if let player {
                    VideoPlayer(player: player).aspectRatio(9.0 / 16.0, contentMode: .fit)
                } else {
                    ProgressView().tint(.white)
                }
            } else if let image {
                ZoomableImage(image: image, isZoomed: $localZoom)
                    .onLongPressGesture(minimumDuration: 0.6) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        askDelete()
                    }
                    .transition(.opacity)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(record.id)-\(record.presetID)-\(record.evPushPull)") {
            if record.kind == .video {
                player = AVPlayer(url: model.url(.video, for: record))
            } else {
                let url = model.url(.processed, for: record)
                let loaded = await Task.detached { UIImage(contentsOfFile: url.path) }.value
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
        }
        .onChange(of: isCurrent) { _, shown in
            if !shown { player?.pause() }
        }
        .onChange(of: localZoom) { _, value in
            if isCurrent { zoomed = value }
        }
    }
}

/// A photo that pinches to zoom (up to 5×) and pans while zoomed. A double tap zooms to 2.5× or back to fit.
struct ZoomableImage: View {
    let image: UIImage
    @Binding var isZoomed: Bool

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        scale = min(max(lastScale * value.magnification, 1), 5)
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1 { reset() }
                        isZoomed = scale > 1
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard scale > 1 else { return }
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in lastOffset = offset }
            )
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if scale > 1 {
                            reset()
                        } else {
                            scale = 2.5
                            lastScale = 2.5
                            isZoomed = true
                        }
                    }
                }
            )
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
        isZoomed = false
    }
}
