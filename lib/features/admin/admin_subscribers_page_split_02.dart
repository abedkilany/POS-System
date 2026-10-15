part of 'admin_subscribers_page.dart';

class _SubscribersToolbar extends StatelessWidget {
  const _SubscribersToolbar({
    required this.count,
    required this.total,
    required this.controller,
    required this.statusFilter,
    required this.onStatusChanged,
  });

  final int count;
  final int total;
  final TextEditingController controller;
  final String statusFilter;
  final ValueChanged<String?> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tr = AppLocalizations.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 320,
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: tr.text('search_admin_subscribers'),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String>(
            initialValue: statusFilter,
            decoration: InputDecoration(
              labelText: tr.text('subscription_status'),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(
                  value: 'all', child: Text(tr.text('all_statuses'))),
              DropdownMenuItem(value: 'trial', child: Text(tr.text('trial'))),
              DropdownMenuItem(value: 'active', child: Text(tr.text('active'))),
              DropdownMenuItem(
                  value: 'expired', child: Text(tr.text('expired'))),
              DropdownMenuItem(
                  value: 'blocked', child: Text(tr.text('blocked'))),
              DropdownMenuItem(
                  value: 'cancelled', child: Text(tr.text('cancelled'))),
            ],
            onChanged: onStatusChanged,
          ),
        ),
        Chip(
          avatar: const Icon(Icons.filter_list, size: 18),
          label: Text(
              tr.format('shown_of_total', {'count': count, 'total': total})),
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
      ],
    );
  }
}

class _SubscriberIdentity extends StatelessWidget {
  const _SubscriberIdentity({required this.subscriber});

  final AdminSubscriber subscriber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 18,
          child: Text(
            subscriber.username.isEmpty
                ? '?'
                : subscriber.username.characters.first.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subscriber.loginName,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              subscriber.accountStatus.isEmpty
                  ? 'account'
                  : subscriber.accountStatus,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

class _StoreCell extends StatelessWidget {
  const _StoreCell({required this.subscriber});

  final AdminSubscriber subscriber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = subscriber.storeName.isEmpty
        ? subscriber.storeSlug
        : subscriber.storeName;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name.isEmpty ? '-' : name,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        if (subscriber.storeSlug.isNotEmpty)
          Text('@${subscriber.storeSlug}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _PlanBadge extends StatelessWidget {
  const _PlanBadge({required this.plan});

  final String plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = plan.trim().isEmpty ? '-' : plan.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w700)),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(
      {required this.label, required this.color, required this.background});

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w800)),
    );
  }
}

class _TrialCell extends StatelessWidget {
  const _TrialCell(
      {required this.date, required this.remaining, required this.isExpired});

  final String date;
  final String remaining;
  final bool isExpired;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(date),
        Text(
          remaining,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isExpired
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ActionsCell extends StatelessWidget {
  const _ActionsCell({
    required this.onEdit,
    required this.onDelete,
    required this.onResetPassword,
  });

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onResetPassword;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: tr.text('issue_password_reset'),
          child: IconButton(
            icon: const Icon(Icons.password_outlined),
            onPressed: onResetPassword,
          ),
        ),
        Tooltip(
          message: tr.text('edit_subscriber'),
          child: IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
          ),
        ),
        Tooltip(
          message: tr.text('delete_subscriber'),
          child: IconButton(
            icon: Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.error),
            onPressed: onDelete,
          ),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
            TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(tr.text('retry'))),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tr = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(44),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_outlined,
                size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(tr.text('no_subscribers_found'),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(tr.text('try_changing_search_text_or_status_filter'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(
      {required this.label, required this.value, required this.icon});

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 188,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text(value.toString(),
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
