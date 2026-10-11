import Foundation
@main struct CoverageTests {
 static func main() {
  let coverage = PayloadCoverage()
  assert(!coverage.record(rangeHeader: "bytes=0-1023", size: 10000))
  assert(!coverage.record(rangeHeader: "bytes=5000-", size: 10000))
  assert(coverage.record(rangeHeader: "bytes=1024-4999", size: 10000))
  assert(coverage.isComplete)
  assert(PayloadCoverage().record(rangeHeader: nil, size: 10000))
  assert(PayloadCoverage().record(rangeHeader: "bytes=0-", size: 10000))
  assert(PayloadCoverage().record(rangeHeader: "bytes=-10000", size: 10000))
  assert(!PayloadCoverage().record(rangeHeader: "bytes=-1024", size: 10000))
  assert(!PayloadCoverage().record(rangeHeader: "bytes=99999-", size: 10000))
  assert(!PayloadCoverage().record(rangeHeader: "invalid", size: 10000))
  assert(!PayloadCoverage().record(rangeHeader: nil, size: 0))
  let overlap = PayloadCoverage()
  assert(!overlap.record(rangeHeader: "bytes=0-5999", size: 10000))
  assert(overlap.record(rangeHeader: "bytes=3000-9999", size: 10000))
  print("13 payload range checks passed")
 }
}
