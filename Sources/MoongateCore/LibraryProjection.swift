import Foundation

public enum LibraryFilter: Sendable, Equatable {
    case all
    case active
    case needsAttention
    case completed
    case pinned
    case tag(String)
}

/// The small, UI-facing read model. Queue state can be supplied as an overlay
/// keyed by the same stable library id; this keeps a running task in place
/// instead of adding a second, transient list row.
public struct LibraryProjectedItem: Sendable, Equatable, Identifiable {
    public var id: UUID { item.id }
    public let item: LibraryItem
    public let processing: ProcessingSummary?

    public init(item: LibraryItem, processing: ProcessingSummary?) {
        self.item = item
        self.processing = processing
    }
}

public enum LibraryProjection {
    public static func items(
        in envelope: LibraryEnvelope,
        filter: LibraryFilter = .all,
        searchQuery: String = "",
        liveProcessing: [UUID: ProcessingSummary] = [:]
    ) -> [LibraryProjectedItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let projections = envelope.items.map { item in
            LibraryProjectedItem(
                item: item,
                processing: liveProcessing[item.id] ?? item.latestVersion?.processing
            )
        }

        return projections
            .filter { matches($0, filter: filter) }
            .filter { matches($0, searchQuery: query) }
            .sorted(by: sort)
    }

    private static func matches(_ projection: LibraryProjectedItem, filter: LibraryFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .active:
            return projection.processing?.state.isActive == true
        case .needsAttention:
            return projection.processing?.state.needsAttention == true
        case .completed:
            return projection.processing?.state == .completed
        case .pinned:
            return projection.item.isPinned
        case .tag(let tag):
            return projection.item.tags.contains {
                $0.compare(tag, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }
    }

    private static func matches(_ projection: LibraryProjectedItem, searchQuery: String) -> Bool {
        guard !searchQuery.isEmpty else { return true }
        let searchable = [projection.item.title, projection.item.note ?? ""] + projection.item.tags
        return searchable.contains {
            $0.range(of: searchQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private static func sort(_ lhs: LibraryProjectedItem, _ rhs: LibraryProjectedItem) -> Bool {
        if lhs.item.isPinned != rhs.item.isPinned {
            return lhs.item.isPinned
        }

        let lhsActive = lhs.processing?.state.isActive == true
        let rhsActive = rhs.processing?.state.isActive == true
        if lhsActive != rhsActive {
            return lhsActive
        }

        if lhs.item.updatedAt != rhs.item.updatedAt {
            return lhs.item.updatedAt > rhs.item.updatedAt
        }

        return lhs.item.title.localizedStandardCompare(rhs.item.title) == .orderedAscending
    }
}
