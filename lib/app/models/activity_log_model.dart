import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

class ActivityLog {
  final Timestamp? timestamp;
  final GeoPoint? location;
  final String? status;
  // This is the key change to make the address reactive
  final RxString address = 'Loading address...'.obs;

  ActivityLog({
    this.timestamp,
    this.location,
    this.status,
  });

  factory ActivityLog.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return ActivityLog(
      timestamp: data['timestamp'],
      // Corrected field name to match your Firestore data
      location: data['location'],
      status: data['status'],
    );
  }
}