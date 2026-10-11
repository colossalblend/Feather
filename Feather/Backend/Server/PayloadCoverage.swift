import Foundation

/// A successful range probe is not a successful transfer of the entire IPA.
final class PayloadCoverage: @unchecked Sendable {
	private let lock = NSLock()
	private var ranges: [ClosedRange<Int64>] = []
	private var complete = false
	var isComplete: Bool {
		lock.lock(); defer { lock.unlock() }
		return complete
	}

	func record(rangeHeader: String?, size: Int64) -> Bool {
		lock.lock(); defer { lock.unlock() }
		guard size > 0 else { return false }
		guard let header = rangeHeader else { complete = true; return true }
		guard header.hasPrefix("bytes="), !header.contains(",") else { return complete }
		let parts = header.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
		guard parts.count == 2 else { return complete }
		let lower: Int64, upper: Int64
		if parts[0].isEmpty {
			guard let suffix = Int64(parts[1]), suffix > 0 else { return complete }
			lower = max(0, size - suffix); upper = size - 1
		} else {
			guard let start = Int64(parts[0]), start >= 0, start < size else { return complete }
			lower = start
			if parts[1].isEmpty { upper = size - 1 }
			else {
				guard let end = Int64(parts[1]), end >= start else { return complete }
				upper = min(size - 1, end)
			}
		}
		ranges.append(lower...upper)
		var merged: [ClosedRange<Int64>] = []
		for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
			if let last = merged.last, range.lowerBound <= last.upperBound + 1 {
				merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
			} else { merged.append(range) }
		}
		ranges = merged
		complete = ranges.first == (0...(size - 1))
		return complete
	}
}
