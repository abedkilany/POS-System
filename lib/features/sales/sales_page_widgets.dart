part of 'sales_page.dart';

class _EmbeddedScannerError extends StatelessWidget {
  const _EmbeddedScannerError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return ColoredBox(
        color: Colors.black,
        child: Center(
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline,
                      color: Colors.white, size: 24),
                  const SizedBox(height: 8),
                  Text(tr.text('camera_scanner_error'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.white)),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: Text(tr.text('retry')))
                ]))));
  }
}

class _MobileSaleAction extends StatelessWidget {
  const _MobileSaleAction(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon),
              const SizedBox(height: 2),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall)
            ])));
  }
}

class _AccessDeniedScaffold extends StatelessWidget {
  const _AccessDeniedScaffold({required this.title, required this.message});
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.lock_outline, size: 42),
                          const SizedBox(height: 12),
                          Text(title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Text(message, textAlign: TextAlign.center)
                        ]))))));
  }
}
