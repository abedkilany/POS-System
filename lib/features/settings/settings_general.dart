part of 'settings_page.dart';

extension _SettingsGeneralSections on SettingsPage {
  List<Widget> _organizedGeneralCards(BuildContext context) =>
      _generalCards(context);

  List<Widget> _organizedBranchCards(BuildContext context) => <Widget>[
        ..._branchCards(context),
        _SaleWarehouseSettingsCard(store: store),
      ];
}
