import AVFoundation
import CameraCore
import SwiftUI

/// Redevelop a recorded Log video, laid out as Kino's grading sheet: the clip plays with the chosen look along
/// the top of the sheet, the looks run along the bottom, and Render writes the clip only once something has
/// changed. Tap the picture to pause.
struct VideoRedevelopView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let recordID: UUID

    @State private var presetID = ""
    @State private var grainLevel = GrainLevel.medium
    @State private var halationLevel = EffectLevel.medium
    @State private var player = AVPlayer()
    @State private var clipSize = CGSize(width: 16, height: 9)
    @State private var clipAngle: CGFloat = 0
    @State private var isRendering = false

    private var record: CaptureRecord? { model.captures.first { $0.id == recordID } }
    private var progress: Double? { model.videoProgress[recordID] }
    private var renderKey: String { "\(presetID)|\(grainLevel)|\(halationLevel)" }

    /// Render is offered only when the look differs from the one the clip has now.
    private var hasChanges: Bool {
        guard let record else { return false }
        return presetID != record.presetID || grainLevel != record.grainLevel || halationLevel != record.halationLevel
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                }
                .disabled(isRendering)
                Spacer()
                Text("Redevelop").font(.system(size: 17, weight: .semibold))
                Spacer()
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).hidden()
            }
            .foregroundStyle(.white)
            .padding(.top, 6)

            GradedClipPlayer(player: player, size: clipSize, angle: clipAngle)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.08)))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
                .onTapGesture { togglePlayback() }
                .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 15))
                Text("Look").font(.system(size: 15, weight: .semibold))
                Spacer()
                LevelToggle(title: "GRAIN", level: grainLevel) { grainLevel = grainLevel.next }
                LevelToggle(title: "HALATION", level: halationLevel) { halationLevel = halationLevel.next }
            }
            .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.visiblePresets) { preset in
                        PresetCard(preset: preset, isSelected: preset.id == presetID, thumbnail: nil) {
                            presetID = preset.id
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 96)

            if let progress {
                VStack(spacing: 4) {
                    ProgressView(value: progress).tint(Theme.accent)
                    Text("Rendering \(Int(progress * 100))% · keep the app open")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            HStack(spacing: 12) {
                if hasChanges {
                    Button(action: render) {
                        Text(isRendering ? "Rendering…" : "Render")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Capsule().fill(Theme.accent))
                    }
                    .disabled(isRendering || presetID.isEmpty)
                } else {
                    Spacer()
                }
                if let record {
                    ShareLink(item: model.shareURL(for: record)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Theme.chrome))
                    }
                    .disabled(isRendering)
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isRendering)
        .onAppear {
            guard let record else { return }
            presetID = record.presetID
            grainLevel = record.grainLevel
            halationLevel = record.halationLevel
            player.play()
        }
        .onDisappear {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        .task { await loadClipShape() }
        .task(id: renderKey) { await updatePlayback() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
            player.seek(to: .zero) { _ in player.play() }
        }
    }

    private func togglePlayback() {
        if player.timeControlStatus == .playing { player.pause() } else { player.play() }
    }

    /// The stored frames are landscape; the track says how the phone turned them.
    private func loadClipShape() async {
        guard let record else { return }
        let asset = AVURLAsset(url: model.url(.video, for: record))
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform)
        else { return }
        clipSize = size
        clipAngle = atan2(transform.b, transform.a)
    }

    /// Grades the clip again after each change, and keeps it playing where it was. A quick run of changes
    /// only builds the last one.
    private func updatePlayback() async {
        guard let record, !presetID.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(200))
        if Task.isCancelled { return }
        guard let look = await model.videoDevelopLook(presetID: presetID, grain: grainLevel, halation: halationLevel) else { return }
        let url = model.url(.video, for: record)
        guard let item = try? await LogGradePreview.playerItem(url: url, look: look), !Task.isCancelled else { return }
        let time = player.currentTime()
        let wasPlaying = player.timeControlStatus == .playing || player.currentItem == nil
        player.replaceCurrentItem(with: item)
        player.seek(to: time) { _ in
            if wasPlaying { player.play() }
        }
    }

    private func render() {
        guard let record, !presetID.isEmpty else { return }
        isRendering = true
        Task {
            let ok = await model.redevelopVideo(record, presetID: presetID, grain: grainLevel, halation: halationLevel)
            isRendering = false
            if ok { dismiss() }
        }
    }
}

/// The clip on the player layer, turned as the phone turned it and fitted to the space it is given.
struct GradedClipPlayer: UIViewRepresentable {
    let player: AVPlayer
    let size: CGSize
    let angle: CGFloat

    func makeUIView(context: Context) -> ClipContainer {
        let container = ClipContainer()
        container.playerView.player = player
        return container
    }

    func updateUIView(_ container: ClipContainer, context: Context) {
        container.playerView.player = player
        container.size = size
        container.angle = angle
    }
}

final class ClipContainer: UIView {
    let playerView = PlayerView()
    var size = CGSize(width: 16, height: 9) {
        didSet { setNeedsLayout() }
    }
    var angle: CGFloat = 0 {
        didSet { setNeedsLayout() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        addSubview(playerView)
    }

    required init?(coder: NSCoder) {
        fatalError("ClipContainer is built in code")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A quarter turn swaps the sides, so the frames are fitted as they will be shown.
        let quarterTurned = abs(sin(angle)) > 0.5
        let shown = quarterTurned ? CGSize(width: size.height, height: size.width) : size
        guard shown.width > 0, shown.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        let scale = min(bounds.width / shown.width, bounds.height / shown.height)
        playerView.transform = .identity
        playerView.bounds = CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
        playerView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        playerView.transform = CGAffineTransform(rotationAngle: angle)
    }
}

final class PlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var player: AVPlayer? {
        get { (layer as? AVPlayerLayer)?.player }
        set {
            (layer as? AVPlayerLayer)?.player = newValue
            (layer as? AVPlayerLayer)?.videoGravity = .resizeAspect
        }
    }
}
