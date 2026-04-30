class StoreProfile {
  const StoreProfile({
    required this.name,
    required this.phone,
    required this.address,
    required this.currency,
    required this.footerNote,
  });

  final String name;
  final String phone;
  final String address;
  final String currency;
  final String footerNote;

  StoreProfile copyWith({
    String? name,
    String? phone,
    String? address,
    String? currency,
    String? footerNote,
  }) {
    return StoreProfile(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      currency: currency ?? this.currency,
      footerNote: footerNote ?? this.footerNote,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'address': address,
        'currency': currency,
        'footerNote': footerNote,
      };

  factory StoreProfile.fromJson(Map<String, dynamic> json) => StoreProfile(
        name: json['name'] as String? ?? 'My Store',
        phone: json['phone'] as String? ?? '',
        address: json['address'] as String? ?? '',
        currency: json['currency'] as String? ?? 'USD',
        footerNote: json['footerNote'] as String? ?? 'Thank you for shopping with us.',
      );

  static const defaults = StoreProfile(
    name: 'My Store',
    phone: '',
    address: '',
    currency: 'USD',
    footerNote: 'Thank you for shopping with us.',
  );
}
