part of 'maintenance_page.dart';

class MaintenancePage extends StatefulWidget {
  const MaintenancePage({super.key, required this.store});

  final ApplicationSession store;

  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}
