part of 'settings_page.dart';

extension _SettingsPrinterSection on SettingsPage {
  List<Widget> _printerCards(BuildContext context) => <Widget>[
        _thermalPrinterCard(context),
      ];
}
