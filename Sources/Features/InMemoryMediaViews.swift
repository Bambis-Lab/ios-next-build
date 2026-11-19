import AVFoundation
import AVKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AudioPlayback: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayback()
    private var player: AVAudioPlayer?
    private var audioLease: UUID?

    func toggle(_ data: Data) {
        if player?.isPlaying == true {
            stop()
            return
        }
        // Retire a finished/interrupted player and its lease before replacing it.
        stop()
        audioLease = AppAudioCoordinator.shared.begin(.chatVoicePlayback)
        player = try? AVAudioPlayer(data: data)
        guard let player else {
            AppAudioCoordinator.shared.end(audioLease)
            audioLease = nil
            return
        }
        player.delegate = self
        player.prepareToPlay()
        guard player.play() else {
            self.player = nil
            AppAudioCoordinator.shared.end(audioLease)
            audioLease = nil
            return
        }
    }

    func stop() {
        let previous=player
        player=nil
        previous?.delegate=nil
        previous?.stop()
        AppAudioCoordinator.shared.end(audioLease)
        audioLease=nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard self.player === player else {return}
        stop()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard self.player === player else {return}
        stop()
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

/// Resolve AVFoundation's requested range without negative offsets, integer
/// overflow, or sending an already-consumed prefix again. EOF is a valid
/// empty range; malformed offsets fail closed.
enum MemoryMediaByteRange {
    static func resolve(byteCount:Int,requestedOffset:Int64,currentOffset:Int64,
                        requestedLength:Int,allToEnd:Bool) throws -> Range<Int> {
        guard byteCount>=0,requestedLength>=0,requestedOffset>=0,currentOffset>=0,
              let start=Int(exactly:requestedOffset),start<=byteCount else {
            throw ChatError.unsupportedMedia
        }
        let position=currentOffset==0 ? requestedOffset : currentOffset
        guard let offset=Int(exactly:position),offset>=start,offset<=byteCount else {
            throw ChatError.unsupportedMedia
        }
        let available=byteCount-offset
        if allToEnd {return offset..<byteCount}
        let consumed=offset-start
        guard consumed<=requestedLength else {throw ChatError.unsupportedMedia}
        let remaining=requestedLength-consumed
        return offset..<(offset+min(remaining,available))
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
            do {
                let range=try MemoryMediaByteRange.resolve(byteCount:data.count,
                    requestedOffset:request.requestedOffset,currentOffset:request.currentOffset,
                    requestedLength:request.requestedLength,allToEnd:request.requestsAllDataToEndOfResource)
                if !range.isEmpty {
                    request.respond(with:data.subdata(in:(data.startIndex+range.lowerBound)..<(data.startIndex+range.upperBound)))
                }
            } catch {
                loadingRequest.finishLoading(with:error)
                return true
            }
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
    @Environment(\.scenePhase) private var scenePhase

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
            controller?.player.pause()
            controller = MemoryVideoController(data: data, contentType: contentType)
        }
        .onChange(of:scenePhase) { _,phase in
            if phase != .active {controller?.player.pause()}
        }
        .onDisappear {
            controller?.player.pause()
            controller = nil
        }
    }
}
