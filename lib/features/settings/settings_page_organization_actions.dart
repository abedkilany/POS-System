part of 'settings_page.dart';

extension _OrganizationActions on SettingsPage {
  Future<void> _editBranch(BuildContext context, StoreProfile profile,
      OrganizationBranch? branch) async {
    final nameController = TextEditingController(text: branch?.name ?? '');
    final codeController = TextEditingController(text: branch?.code ?? '');
    final addressController =
        TextEditingController(text: branch?.address ?? '');
    final phoneController = TextEditingController(text: branch?.phone ?? '');
    var isActive = branch?.isActive ?? true;
    final tr = AppLocalizations.of(context);

    final result = await showDialog<OrganizationBranch>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text(branch == null
                ? tr.text('add_branch')
                : tr.text('edit_branch')),
            content: ResponsiveDialogBox(
              maxWidth: VentioResponsive.modalMaxWidth(context, 560),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration:
                          InputDecoration(labelText: tr.text('branch_name')),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: codeController,
                      decoration:
                          InputDecoration(labelText: tr.text('branch_code')),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      decoration: InputDecoration(labelText: tr.text('phone')),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressController,
                      minLines: 2,
                      maxLines: 4,
                      decoration:
                          InputDecoration(labelText: tr.text('address')),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: isActive,
                      onChanged: (value) => setState(() => isActive = value),
                      title: Text(tr.text('active')),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(tr.text('cancel'))),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(
                    dialogContext,
                    OrganizationBranch(
                      id: branch?.id ??
                          'branch_${DateTime.now().microsecondsSinceEpoch}',
                      name: name,
                      code: codeController.text.trim(),
                      address: addressController.text.trim(),
                      phone: phoneController.text.trim(),
                      isActive: isActive,
                    ),
                  );
                },
                child: Text(tr.text('save')),
              ),
            ],
          );
        });
      },
    );

    if (result == null) return;
    if (!context.mounted) return;
    final nextBranches = [
      ...profile.branches.where((item) => item.id != result.id),
      result,
    ];
    await _saveOrganizationProfile(
        context, profile.copyWith(branches: nextBranches));
  }

  Future<void> _editOrganizationGeneral(
      BuildContext context, StoreProfile profile) async {
    final nameController = TextEditingController(text: profile.name);
    final tradeNameController = TextEditingController(text: profile.tradeName);
    final phoneController = TextEditingController(text: profile.phone);
    final emailController = TextEditingController(text: profile.email);
    final websiteController = TextEditingController(text: profile.website);
    final tr = AppLocalizations.of(context);

    final result = await showDialog<StoreProfile>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(tr.text('organization_general')),
          content: ResponsiveDialogBox(
            maxWidth: VentioResponsive.modalMaxWidth(context, 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: nameController,
                      decoration:
                          InputDecoration(labelText: tr.text('store_name'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: tradeNameController,
                      decoration:
                          InputDecoration(labelText: tr.text('trade_name'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: phoneController,
                      decoration: InputDecoration(labelText: tr.text('phone'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(labelText: tr.text('email'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: websiteController,
                      keyboardType: TextInputType.url,
                      decoration:
                          InputDecoration(labelText: tr.text('website'))),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  profile.copyWith(
                    name: nameController.text.trim().isEmpty
                        ? tr.text('my_store')
                        : nameController.text.trim(),
                    tradeName: tradeNameController.text.trim(),
                    phone: phoneController.text.trim(),
                    email: emailController.text.trim(),
                    website: websiteController.text.trim(),
                  ),
                );
              },
              child: Text(tr.text('save')),
            ),
          ],
        );
      },
    );

    if (result != null) {
      if (!context.mounted) return;
      await _saveOrganizationProfile(context, result);
    }
  }

  Future<void> _editOrganizationLegal(
      BuildContext context, StoreProfile profile) async {
    final legalNameController = TextEditingController(text: profile.legalName);
    final vatController = TextEditingController(text: profile.vatNumber);
    final taxController =
        TextEditingController(text: profile.taxRegistrationNumber);
    final registerController =
        TextEditingController(text: profile.commercialRegisterNumber);
    final countryController = TextEditingController(text: profile.country);
    final governorateController =
        TextEditingController(text: profile.governorate);
    final cityController = TextEditingController(text: profile.city);
    final addressController = TextEditingController(text: profile.address);
    final tr = AppLocalizations.of(context);

    final result = await showDialog<StoreProfile>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(tr.text('organization_legal')),
          content: ResponsiveDialogBox(
            maxWidth: VentioResponsive.modalMaxWidth(context, 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: legalNameController,
                      decoration:
                          InputDecoration(labelText: tr.text('legal_name'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: vatController,
                      decoration:
                          InputDecoration(labelText: tr.text('vat_number'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: taxController,
                      decoration: InputDecoration(
                          labelText: tr.text('tax_registration_number'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: registerController,
                      decoration: InputDecoration(
                          labelText: tr.text('commercial_register_number'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: countryController,
                      decoration:
                          InputDecoration(labelText: tr.text('country'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: governorateController,
                      decoration:
                          InputDecoration(labelText: tr.text('governorate'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: cityController,
                      decoration: InputDecoration(labelText: tr.text('city'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: addressController,
                      minLines: 2,
                      maxLines: 4,
                      decoration:
                          InputDecoration(labelText: tr.text('address'))),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  profile.copyWith(
                    legalName: legalNameController.text.trim(),
                    vatNumber: vatController.text.trim(),
                    taxRegistrationNumber: taxController.text.trim(),
                    commercialRegisterNumber: registerController.text.trim(),
                    country: countryController.text.trim(),
                    governorate: governorateController.text.trim(),
                    city: cityController.text.trim(),
                    address: addressController.text.trim(),
                  ),
                );
              },
              child: Text(tr.text('save')),
            ),
          ],
        );
      },
    );

    if (result != null) {
      if (!context.mounted) return;
      await _saveOrganizationProfile(context, result);
    }
  }

  Future<void> _editOrganizationBranding(
      BuildContext context, StoreProfile profile) async {
    final footerController = TextEditingController(text: profile.footerNote);
    final tr = AppLocalizations.of(context);
    var logoDataBase64 = profile.logoDataBase64;
    var logoFileName = profile.logoFileName;
    var logoMimeType = profile.logoMimeType;

    String chooseLogoLabel() {
      if (tr.isArabic) return 'اختيار الشعار';
      if (tr.locale.languageCode == 'fr') return 'Choisir le logo';
      return 'Choose logo';
    }

    String removeLogoLabel() {
      if (tr.isArabic) return 'إزالة الشعار';
      if (tr.locale.languageCode == 'fr') return 'Supprimer le logo';
      return 'Remove logo';
    }

    String storedLabel() {
      if (tr.isArabic) {
        return 'يُحفظ الشعار داخل قاعدة البيانات ويُزامن مع الأجهزة.';
      }
      if (tr.locale.languageCode == 'fr') {
        return 'Le logo est stocké dans la base de données et synchronisé entre les appareils.';
      }
      return 'The logo is stored in the database and synced across devices.';
    }

    final result = await showDialog<StoreProfile>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(tr.text('organization_branding')),
            content: ResponsiveDialogBox(
              maxWidth: VentioResponsive.modalMaxWidth(context, 560),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (logoDataBase64.isNotEmpty) ...[
                      Container(
                        height: 120,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: Theme.of(context).dividerColor),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Image.memory(
                          base64Decode(logoDataBase64),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        logoFileName.isEmpty ? storedLabel() : logoFileName,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked =
                                  await FilePicker.platform.pickFiles(
                                type: FileType.image,
                                withData: true,
                                allowMultiple: false,
                              );
                              if (picked == null || picked.files.isEmpty) {
                                return;
                              }
                              final file = picked.files.single;
                              final bytes = file.bytes;
                              if (bytes == null || bytes.isEmpty) return;
                              const maxLogoBytes = 2 * 1024 * 1024;
                              if (bytes.length > maxLogoBytes) {
                                if (!dialogContext.mounted) return;
                                ScaffoldMessenger.of(dialogContext)
                                    .showSnackBar(
                                  SnackBar(
                                    content: Text(tr.text('logo_too_large')),
                                  ),
                                );
                                return;
                              }
                              final extension =
                                  (file.extension ?? '').toLowerCase();
                              final mime = switch (extension) {
                                'jpg' || 'jpeg' => 'image/jpeg',
                                'webp' => 'image/webp',
                                'gif' => 'image/gif',
                                _ => 'image/png',
                              };
                              setDialogState(() {
                                logoDataBase64 = base64Encode(bytes);
                                logoFileName = file.name;
                                logoMimeType = mime;
                              });
                            },
                            icon: const Icon(Icons.image_outlined),
                            label: Text(chooseLogoLabel()),
                          ),
                        ),
                        if (logoDataBase64.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: removeLogoLabel(),
                            onPressed: () => setDialogState(() {
                              logoDataBase64 = '';
                              logoFileName = '';
                              logoMimeType = '';
                            }),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      storedLabel(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: footerController,
                      minLines: 2,
                      maxLines: 4,
                      decoration:
                          InputDecoration(labelText: tr.text('invoice_footer')),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(tr.text('cancel'))),
              FilledButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                    profile.copyWith(
                      logoPath: '',
                      logoDataBase64: logoDataBase64,
                      logoFileName: logoFileName,
                      logoMimeType: logoMimeType,
                      footerNote: footerController.text.trim().isEmpty
                          ? tr.text('default_invoice_footer')
                          : footerController.text.trim(),
                    ),
                  );
                },
                child: Text(tr.text('save')),
              ),
            ],
          ),
        );
      },
    );

    if (result != null) {
      if (!context.mounted) return;
      await _saveOrganizationProfile(context, result);
    }
  }

  Future<void> _saveOrganizationProfile(
      BuildContext context, StoreProfile profile) async {
    final tr = AppLocalizations.of(context);
    await store.runtime.updateStoreProfile(profile);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('store_profile_updated'))));
    }
  }
}
