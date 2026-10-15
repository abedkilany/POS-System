part of 'settings_page.dart';

class _SettingsNavData {
  const _SettingsNavData(
      {required this.icon, required this.label, required this.description});

  final IconData icon;
  final String label;
  final String description;
}

class _SettingsSection {
  const _SettingsSection({required this.nav, required this.pageBuilder});

  final _SettingsNavData nav;
  final WidgetBuilder pageBuilder;
}

class _DeferredSettingsPage extends StatelessWidget {
  const _DeferredSettingsPage({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => builder(context);
}

class _SettingsSideNav extends StatelessWidget {
  const _SettingsSideNav(
      {required this.items,
      required this.selectedIndex,
      required this.onSelected});

  final List<_SettingsNavData> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SettingsNavItem(
              item: items[i],
              selected: selectedIndex == i,
              onTap: () => onSelected(i),
            ),
          ),
      ],
    );
  }
}

class _SettingsNavItem extends StatelessWidget {
  const _SettingsNavItem(
      {required this.item, required this.selected, required this.onTap});

  final _SettingsNavData item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.45)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.14)
                  : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(item.icon,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: selected ? colorScheme.primary : null,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(item.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 20,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _VentioBrandHeader extends StatelessWidget {
  const _VentioBrandHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.55),
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1218),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                'assets/branding/ventio_app_icon_1024.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.storefront_outlined,
                  color: colorScheme.primary,
                  size: 34,
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
