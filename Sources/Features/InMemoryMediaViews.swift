import AVFoundation
import AVKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private final class AudioPlayback: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayback()
    private var player: AVAudioPlayer?

    func toggle(_ data: Data) {
        if player?.isPlaying == true {
            player?.stop()
            player = nil
            return
        }
        player = try? AVAudioPlayer(data: data)
        player?.delegate = self
        player?.prepareToPlay()
        player?.play()
    }
}

struct InMemoryAudioButton: View {
    let data: Data

    var body: some View {
        Button {
            AudioPlayback.shared.toggle(data)
        } label: {
            Label("Sprachnachricht abspielen", systemImage: "play.fill")
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
    }
}

private final class MemoryAssetLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    let data: Data
    let contentType: String

    init(data: Data, contentType: String) {
        self.data = data
        self.contentType = contentType
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        if let information = loadingRequest.contentInformationRequest {
            information.contentType = UTType(mimeType: contentType)?.identifier ?? UTType.movie.identifier
            information.contentLength = Int64(data.count)
            information.isByteRangeAccessSupported = true
        }
        if let request = loadingRequest.dataRequest {
            let offset = Int(request.currentOffset > 0 ? request.currentOffset : request.requestedOffset)
            let available = max(0, data.count - offset)
            let length = min(request.requestedLength, available)
            if length > 0 { request.respond(with: data.subdata(in: offset..<(offset + length))) }
        }
        loadingRequest.finishLoading()
        return true
    }
}

@MainActor
private final class MemoryVideoController {
    let player: AVPlayer
    private let loader: MemoryAssetLoader

    init(data: Data, contentType: String) {
        loader = MemoryAssetLoader(data: data, contentType: contentType)
        let fileExtension = UTType(mimeType: contentType)?.preferredFilenameExtension ?? "mp4"
        let url = URL(string: "iosnext-memory://video/\(UUID().uuidString).\(fileExtension)")!
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(loader, queue: DispatchQueue(label: "iosnext.memory-video"))
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
    }
}

struct InMemoryVideoView: View {
    let id: String
    let data: Data
    let contentType: String
    @State private var controller: MemoryVideoController?

    var body: some View {
        Group {
            if let controller {
                VideoPlayer(player: controller.player)
            } else {
                ProgressView()
            }
        }
        .frame(minHeight: 190)
        .task(id: id) {
            controller = MemoryVideoController(data: data, contentType: contentType)
        }
        .onDisappear {
            controller?.player.pause()
            controller = nil
        }
    }
}
