import Foundation

struct UsageRenderer {
    func render() -> String {
        """
        Usage:
          fan status
          fan auto
          fan max
          fan set <percent>
          fan help

        Notes:
          - `set <percent>` targets the given percentage of each fan's maximum RPM.
          - Values below a fan's minimum RPM are clamped to that fan's minimum.
        """
    }
}
