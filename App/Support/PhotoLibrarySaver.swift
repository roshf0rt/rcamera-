import Photos

enum PhotoLibrarySaver {
    enum SaveError: LocalizedError {
        case denied

        var errorDescription: String? { "Photo library access is off. Allow it in Settings to save captures." }
    }

    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }

    static func savePhoto(heicURL: URL, rawURL: URL?) async throws {
        guard await requestAccess() else { throw SaveError.denied }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: heicURL, options: nil)
            if let rawURL {
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .alternatePhoto, fileURL: rawURL, options: options)
            }
        }
    }

    static func saveVideo(url: URL) async throws {
        guard await requestAccess() else { throw SaveError.denied }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .video, fileURL: url, options: nil)
        }
    }
}
