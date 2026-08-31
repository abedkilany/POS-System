part of 'settings_page.dart';

extension _SettingsDevicesSection on SettingsPage {
  List<Widget> _deviceCards(BuildContext context) => <Widget>[
        _SystemIdentityCard(store: store),
        const _ScannerFeedbackSettingsCard(),
        _CurrentDeviceCashDrawerSettingsCard(store: store),
      ];
}
