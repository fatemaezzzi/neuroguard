import 'package:cloud_firestore/cloud_firestore.dart';

enum AlertType { geoFence, medicine, spyCall, matSensor }
enum AlertSeverity { info, warning, critical }

class AlertModel {
  final AlertType type;
  final String message;
  final AlertSeverity severity;
  final Map<String, dynamic> metadata;

  const AlertModel({
    required this.type,
    required this.message,
    this.severity = AlertSeverity.warning,
    this.metadata = const {},
  });

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'message': message,
    'severity': severity.name,
    'timestamp': FieldValue.serverTimestamp(),
    'isRead': false,
    'metadata': metadata,
  };
}