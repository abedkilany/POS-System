part of 'settings_page.dart';

extension _SettingsSyncSection on SettingsPage {
  List<Widget> _organizedSyncCards(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return <Widget>[
      _SettingsSectionIntro(
        title: tr.text('sync_overview'),
        description: tr.text('sync_overview_desc'),
        sections: <String>[
          'sync_method',
          'sync_pair_devices',
          'sync_connected_devices',
          'sync_monitoring_diagnostics',
          'sync_advanced_settings',
        ].map(tr.text).toList(),
      ),
      ..._syncCards(context),
    ];
  }
}

class _SettingsSectionIntro extends StatelessWidget {
  const _SettingsSectionIntro({
    required this.title,
    required this.description,
    required this.sections,
  });

  final String title;
  final String description;
  final List<String> sections;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: VentioResponsive.pageInsets(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(description),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: sections
                    .map((section) => Chip(label: Text(section)))
                    .toList(),
              ),
            ],
          ),
        ),
      );
}
