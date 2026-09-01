/// Shared orchestration contract for safely editing posted business documents.
///
/// Callers are responsible for executing this pipeline inside their authoritative
/// database transaction. The pipeline deliberately does not catch failures so
/// the surrounding transaction can roll back every reversed/rebuilt effect.
class PostedDocumentEditPipeline<T> {
  const PostedDocumentEditPipeline({
    required this.loadAuthoritative,
    required this.validatePermission,
    required this.validateVersion,
    required this.validateDependencies,
    required this.reverseOperationalEffects,
    required this.reverseAccountingEffects,
    required this.applyChanges,
    required this.rebuildOperationalEffects,
    required this.buildPostedSnapshot,
    required this.repostAccounting,
    required this.rebuildDerivedState,
    required this.verifyIntegrity,
  });

  final Future<T> Function() loadAuthoritative;
  final Future<void> Function(T current) validatePermission;
  final Future<void> Function(T current) validateVersion;
  final Future<void> Function(T current) validateDependencies;
  final Future<void> Function(T current) reverseOperationalEffects;
  final Future<void> Function(T current) reverseAccountingEffects;
  final Future<T> Function(T current) applyChanges;
  final Future<T> Function(T updated) rebuildOperationalEffects;
  final Future<T> Function(T updated) buildPostedSnapshot;
  final Future<void> Function(T updated) repostAccounting;
  final Future<void> Function(T updated) rebuildDerivedState;
  final Future<void> Function(T updated) verifyIntegrity;

  Future<T> execute() async {
    final current = await loadAuthoritative();
    await validatePermission(current);
    await validateVersion(current);
    await validateDependencies(current);
    await reverseOperationalEffects(current);
    await reverseAccountingEffects(current);
    var updated = await applyChanges(current);
    updated = await rebuildOperationalEffects(updated);
    updated = await buildPostedSnapshot(updated);
    await repostAccounting(updated);
    await rebuildDerivedState(updated);
    await verifyIntegrity(updated);
    return updated;
  }
}
