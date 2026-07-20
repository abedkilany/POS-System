import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/features/dev_tools/stress_lab_coverage_manifest.dart';

void main() {
  test('Stress Lab coverage manifest has unique page keys and expected counts',
      () {
    final keys = stressLabCoverageManifest.map((entry) => entry.pageKey).toList();
    expect(keys.toSet().length, keys.length, reason: 'Page keys must be unique.');
    expect(keys.toSet(), containsAll(stressLabRegisteredPages.map((page) => page.key)));
    expect(stressLabRegisteredPages.length, stressLabCoverageManifest.length);

    final stateCounts = stressLabCoverageCounts();
    expect(stateCounts[StressLabCoverageState.full], 27);
    expect(stateCounts[StressLabCoverageState.partial], 0);
    expect(stateCounts[StressLabCoverageState.missing], 0);

    final kindCounts = stressLabScenarioCounts();
    expect(kindCounts[StressLabScenarioKind.commerce], 8);
    expect(kindCounts[StressLabScenarioKind.inventory], 2);
    expect(kindCounts[StressLabScenarioKind.accounting], 2);
    expect(kindCounts[StressLabScenarioKind.reports], 1);
    expect(kindCounts[StressLabScenarioKind.settings], 2);
    expect(kindCounts[StressLabScenarioKind.sync], 1);
    expect(kindCounts[StressLabScenarioKind.maintenance], 2);
    expect(kindCounts[StressLabScenarioKind.admin], 3);
    expect(kindCounts[StressLabScenarioKind.system], 4);
    expect(kindCounts[StressLabScenarioKind.tooling], 2);

    expect(
      stressLabCoverageManifest.where((entry) => entry.seedsData).length,
      greaterThan(0),
    );
    expect(
      stressLabCoverageManifest.where((entry) => entry.drivesUi).length,
      greaterThan(0),
    );
    expect(
      stressLabCoverageManifest.where((entry) => entry.assertsState).length,
      greaterThan(0),
    );
  });
}
