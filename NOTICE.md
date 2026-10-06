# Third-Party Notices

Arcload includes or derives from third-party software.

## swift-app-template

Parts of the project structure and build tooling are derived from
[rcarmo/swift-app-template](https://github.com/rcarmo/swift-app-template),
which is distributed under the MIT License.

## Streamline — Pie Chart Remix

The download progress indicator adapts the Pie Chart Remix icon by
[Streamline](https://www.streamlinehq.com/), distributed under
[Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).

The supplied original SVG, including its author/license attribution, is retained
at `Resources/Icons/StreamlinePieChartRemix.svg`. Modifications: the static sector
is rendered as a SwiftUI sector driven by download progress, with a short linear
animation that respects Reduce Motion. The pie inherits the foreground color;
paused task rows use secondary styling and failed task rows use red. The shared
renderer uses a 14-point size in task rows and a 17-point size in the menu bar.
Completion is represented by the system SF Symbol `checkmark.circle.fill`.
The icon design remains subject to CC BY 4.0, separately from the application's
MIT-licensed code.

## Aria2 Next

Arcload bundles the standalone Apple Silicon `aria2-next` executable, pinned to
**2.8.6**, maintained by AnInsomniacy and derived from aria2 by Tatsuhiro Tsujikawa
and contributors. The executable is distributed under GPL-2.0-or-later, separately
from Arcload's MIT-licensed Swift source. It incorporates third-party libraries
listed by `aria2-next --version`; their source and license material are included
in the upstream corresponding-source tree.

- Project: https://github.com/AnInsomniacy/aria2-next
- Pinned corresponding source: https://github.com/AnInsomniacy/aria2-next/tree/v2.8.6
- Source archive: https://github.com/AnInsomniacy/aria2-next/archive/refs/tags/v2.8.6.tar.gz
- GPL license: `Resources/aria2-next-COPYING`
- Binary provenance/checksum: `Resources/aria2-next-release.json`

Distribution must provide the GPL-covered corresponding source in accordance
with the license; the upstream URLs identify it but are not a substitute for a
publisher's source-availability obligations. `Resources/aria2c` is retained
for legacy reference only and is not packaged or executed.

The Arcload source code is licensed separately under the repository's
[MIT License](LICENSE).
