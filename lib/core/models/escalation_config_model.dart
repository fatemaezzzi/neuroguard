// lib/core/models/escalation_config_model.dart
// DEBUG BUILD — tier delays compressed to seconds, revert before release.

import 'package:cloud_firestore/cloud_firestore.dart';

class SecondaryContact {
  final String name;
  final String phone;
  final String relation;

  const SecondaryContact({
    required this.name,
    required this.phone,
    required this.relation,
  });

  factory SecondaryContact.fromMap(Map<String, dynamic> m) => SecondaryContact(
    name:     (m['name']     as String?) ?? 'Contact',
    phone:    (m['phone']    as String?) ?? '',
    relation: (m['relation'] as String?) ?? '',
  );

  Map<String, dynamic> toMap() => {
    'name':     name,
    'phone':    phone,
    'relation': relation,
  };
}

class EscalationConfig {
  final bool   enabled;
  final int    tier1DelaySeconds;
  final int    tier2DelaySeconds;
  final int    tier3DelaySeconds;
  final List<SecondaryContact> secondaryContacts;

  const EscalationConfig({
    this.enabled             = true,
    this.tier1DelaySeconds   = 1,   // DEBUG: was 120 (2 min) — revert for release
    this.tier2DelaySeconds   = 1,   // DEBUG: was 300 (5 min) — revert for release
    this.tier3DelaySeconds   = 2,   // DEBUG: was 600 (10 min) — revert for release
    this.secondaryContacts   = const [],
  });

  factory EscalationConfig.fromMap(Map<String, dynamic> m) => EscalationConfig(
    enabled:           (m['enabled']           as bool?)  ?? true,
    tier1DelaySeconds: (m['tier1DelaySeconds']  as int?)   ?? 1,
    tier2DelaySeconds: (m['tier2DelaySeconds']  as int?)   ?? 1,
    tier3DelaySeconds: (m['tier3DelaySeconds']  as int?)   ?? 2,
    secondaryContacts: ((m['secondaryContacts'] as List<dynamic>?) ?? [])
        .map((e) => SecondaryContact.fromMap(e as Map<String, dynamic>))
        .toList(),
  );

  factory EscalationConfig.fromDoc(DocumentSnapshot doc) =>
      EscalationConfig.fromMap((doc.data() as Map<String, dynamic>?) ?? {});

  factory EscalationConfig.defaults() => const EscalationConfig();

  Map<String, dynamic> toMap() => {
    'enabled':           enabled,
    'tier1DelaySeconds': tier1DelaySeconds,
    'tier2DelaySeconds': tier2DelaySeconds,
    'tier3DelaySeconds': tier3DelaySeconds,
    'secondaryContacts': secondaryContacts.map((c) => c.toMap()).toList(),
  };
}