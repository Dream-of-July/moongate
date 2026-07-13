import AppKit
import Foundation
import ImageIO
import SwiftUI

/// 统一的视频缩略图内容视图。
///
/// 缩略图只会在视图出现在屏幕上后请求；离屏或 URL 改变时，网络与解码任务会被取消。
/// 成功的解码结果进入有数量和内存上限的 LRU 缓存，避免列表滚动反复创建图片对象，同时
/// 不让资料库规模直接转化为常驻内存。
@MainActor
struct VideoThumbnail: View {
    /// 缩略图 URL；为 nil 时直接显示 film 占位。
    let url: URL?
    /// 圆角半径，默认信息卡缩略图规格。
    var cornerRadius: CGFloat = Radius.thumbnailCard
    /// film 占位图标大小；默认 `.body`（等价于不设 font 的原生行为）。
    var placeholderFont: Font = .body
    /// 加载中 ProgressView 的控件尺寸。
    var progressControlSize: ControlSize = .small

    @State private var thumbnailImage: NSImage?
    @State private var isLoading = false
    @State private var isVisible = false
    @State private var requestedURL: URL?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        thumbnailContent
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // 极细描边让缩略图从背景「浮起」，light/dark 两种模式下都能形成清晰边界。
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: Stroke.hairline)
            )
            .onAppear {
                isVisible = true
                reload(for: url)
            }
            .onChange(of: url) { _, nextURL in
                reload(for: nextURL)
            }
            .onDisappear {
                isVisible = false
                loadTask?.cancel()
                loadTask = nil
            }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let thumbnailImage {
            Image(nsImage: thumbnailImage)
                .resizable()
                .scaledToFill()
        } else if isLoading, url != nil {
            // 有 URL 且加载中：轻量进度指示，避免立刻闪现 film 占位。
            Rectangle()
                .fill(.quaternary)
                .overlay(ProgressView().controlSize(progressControlSize))
        } else {
            // 失败 / 无 URL：film 占位。
            Rectangle()
                .fill(.quaternary)
                .overlay(
                    Image(systemName: "film")
                        .font(placeholderFont)
                        .foregroundStyle(.tertiary)
                )
        }
    }

    /// Starts work only after the view is visible. The identity guard discards a
    /// late response from a recycled list row rather than briefly showing the
    /// previous video's image.
    private func reload(for nextURL: URL?) {
        loadTask?.cancel()
        requestedURL = nextURL
        thumbnailImage = nil
        isLoading = false

        guard isVisible, let nextURL else { return }

        if let cached = ThumbnailImageCache.shared.image(for: nextURL) {
            thumbnailImage = cached
            return
        }

        isLoading = true
        loadTask = Task { @MainActor [nextURL] in
            do {
                let decoded = try await ThumbnailImageLoader.loadImage(for: nextURL)
                try Task.checkCancellation()
                guard !Task.isCancelled, isVisible, requestedURL == nextURL else { return }

                ThumbnailImageCache.shared.insert(decoded.image, for: nextURL)
                thumbnailImage = decoded.image
                isLoading = false
            } catch {
                // Cancellation is expected while a List recycles rows. A real
                // failure deliberately falls back to the same quiet film state
                // as a missing thumbnail, without introducing an error card.
                guard !Task.isCancelled, isVisible, requestedURL == nextURL else { return }
                isLoading = false
            }
        }
    }
}

/// A main-actor LRU cache because AppKit image objects are consumed by SwiftUI
/// on the main actor. The explicit limits make memory predictable even for a
/// 1,000-item library; the byte limit normally wins for large source images.
private enum ThumbnailImageCacheLimit {
    static let entryCount = 80
    static let cost = 48 * 1024 * 1024
}

@MainActor
final class ThumbnailImageCache {
    static let shared = ThumbnailImageCache(
        maximumEntryCount: ThumbnailImageCacheLimit.entryCount,
        maximumCost: ThumbnailImageCacheLimit.cost
    )

    private struct Entry {
        let image: NSImage
        let cost: Int
    }

    private let entryCapacity: Int
    private let costCapacity: Int
    private var entries: [URL: Entry] = [:]
    private var leastRecentlyUsedFirst: [URL] = []
    private var currentCost = 0

    init(
        maximumEntryCount: Int = ThumbnailImageCacheLimit.entryCount,
        maximumCost: Int = ThumbnailImageCacheLimit.cost
    ) {
        entryCapacity = max(maximumEntryCount, 1)
        costCapacity = max(maximumCost, 1)
    }

    var entryCount: Int { entries.count }
    var totalCost: Int { currentCost }

    func image(for url: URL) -> NSImage? {
        guard let entry = entries[url] else { return nil }
        markAsMostRecentlyUsed(url)
        return entry.image
    }

    func insert(_ image: NSImage, for url: URL) {
        insert(image, for: url, cost: Self.estimatedCost(of: image))
    }

    func insert(_ image: NSImage, for url: URL, cost: Int) {
        if let replaced = entries.removeValue(forKey: url) {
            currentCost = max(currentCost - replaced.cost, 0)
            leastRecentlyUsedFirst.removeAll { $0 == url }
        }

        let normalizedCost = max(cost, 1)
        entries[url] = Entry(image: image, cost: normalizedCost)
        leastRecentlyUsedFirst.append(url)
        currentCost = Self.saturatingAdd(currentCost, normalizedCost)
        trimToCapacity()
    }

    private func markAsMostRecentlyUsed(_ url: URL) {
        leastRecentlyUsedFirst.removeAll { $0 == url }
        leastRecentlyUsedFirst.append(url)
    }

    private func trimToCapacity() {
        while entries.count > entryCapacity || currentCost > costCapacity {
            guard let oldestURL = leastRecentlyUsedFirst.first else { return }
            leastRecentlyUsedFirst.removeFirst()
            guard let removed = entries.removeValue(forKey: oldestURL) else { continue }
            currentCost = max(currentCost - removed.cost, 0)
        }
    }

    private static func estimatedCost(of image: NSImage) -> Int {
        if let representation = image.representations.max(by: {
            estimatedByteCount(width: $0.pixelsWide, height: $0.pixelsHigh)
                < estimatedByteCount(width: $1.pixelsWide, height: $1.pixelsHigh)
        }) {
            return estimatedByteCount(width: representation.pixelsWide, height: representation.pixelsHigh)
        }
        return estimatedByteCount(
            width: Int(image.size.width.rounded(.up)),
            height: Int(image.size.height.rounded(.up))
        )
    }

    private static func estimatedByteCount(width: Int, height: Int) -> Int {
        let pixels = max(width, 1).multipliedReportingOverflow(by: max(height, 1))
        guard !pixels.overflow else { return .max }
        let bytes = pixels.partialValue.multipliedReportingOverflow(by: 4)
        return bytes.overflow ? .max : max(bytes.partialValue, 1)
    }

    private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        lhs > Int.max - rhs ? .max : lhs + rhs
    }
}

/// AppKit objects are constructed in a utility-priority task and become
/// immutable before the main actor consumes them. This wrapper keeps that
/// narrow handoff explicit rather than making the cache itself cross-actor.
private final class ThumbnailDecodedImage: @unchecked Sendable {
    let image: NSImage

    init(_ image: NSImage) {
        self.image = image
    }
}

private enum ThumbnailImageLoader {
    private enum LoadingError: Error {
        case unsuccessfulResponse
        case unsupportedImage
    }

    /// Large enough for the workbench preview, while capping a decoded source
    /// image before it can consume memory proportional to the original asset.
    private static let maximumDecodedPixelSize = 640

    static func loadImage(for url: URL) async throws -> ThumbnailDecodedImage {
        let data: Data
        if url.isFileURL {
            data = try await Task.detached(priority: .utility) {
                try Data(contentsOf: url, options: .mappedIfSafe)
            }.value
        } else {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (receivedData, response) = try await URLSession.shared.data(for: request)
            if let response = response as? HTTPURLResponse,
               !(200..<300).contains(response.statusCode) {
                throw LoadingError.unsuccessfulResponse
            }
            data = receivedData
        }

        try Task.checkCancellation()
        let decoded = await Task.detached(priority: .utility) {
            autoreleasepool {
                Self.downsampledImage(from: data).map(ThumbnailDecodedImage.init)
            }
        }.value
        guard let decoded else { throw LoadingError.unsupportedImage }
        return decoded
    }

    private static func downsampledImage(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDecodedPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: image, size: .zero)
    }
}
