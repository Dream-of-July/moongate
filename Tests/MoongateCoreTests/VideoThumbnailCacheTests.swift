import AppKit
import XCTest
@testable import Moongate

@MainActor
final class VideoThumbnailCacheTests: XCTestCase {

    func testEvictsLeastRecentlyUsedImageWhenEntryLimitIsReached() {
        let cache = ThumbnailImageCache(maximumEntryCount: 2, maximumCost: .max)
        let firstURL = URL(string: "https://images.example.com/first.jpg")!
        let secondURL = URL(string: "https://images.example.com/second.jpg")!
        let thirdURL = URL(string: "https://images.example.com/third.jpg")!
        let first = NSImage(size: NSSize(width: 16, height: 16))
        let second = NSImage(size: NSSize(width: 16, height: 16))
        let third = NSImage(size: NSSize(width: 16, height: 16))

        cache.insert(first, for: firstURL)
        cache.insert(second, for: secondURL)
        _ = cache.image(for: firstURL)
        cache.insert(third, for: thirdURL)

        XCTAssertTrue(cache.image(for: firstURL) === first)
        XCTAssertNil(cache.image(for: secondURL))
        XCTAssertTrue(cache.image(for: thirdURL) === third)
        XCTAssertEqual(cache.entryCount, 2)
    }

    func testEvictsImagesUntilEstimatedMemoryCostFitsLimit() {
        let cache = ThumbnailImageCache(maximumEntryCount: 10, maximumCost: 1_024)
        let firstURL = URL(string: "https://images.example.com/first.jpg")!
        let secondURL = URL(string: "https://images.example.com/second.jpg")!
        let first = NSImage(size: NSSize(width: 16, height: 16))
        let second = NSImage(size: NSSize(width: 16, height: 16))

        cache.insert(first, for: firstURL, cost: 800)
        cache.insert(second, for: secondURL, cost: 800)

        XCTAssertNil(cache.image(for: firstURL))
        XCTAssertTrue(cache.image(for: secondURL) === second)
        XCTAssertEqual(cache.totalCost, 800)
    }
}
