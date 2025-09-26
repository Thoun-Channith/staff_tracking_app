import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:location/location.dart';
import 'package:staff_tracking_app/app/models/activity_log_model.dart';
import 'package:staff_tracking_app/app/routes/app_pages.dart';
import 'package:intl/intl.dart';
import 'package:geocoding/geocoding.dart' as geocoding;

class HomeController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Location _location = Location();

  StreamSubscription<LocationData>? _locationSubscription;
  StreamSubscription? _activityStreamSubscription;

  // --- OBSERVABLES ---
  var isClockedIn = false.obs;
  var userName = ''.obs;
  var isLoading = false.obs;
  var currentAddress = 'Getting location...'.obs;
  var lastActivityTime = 'N/A'.obs;
  final activityLogs = <ActivityLog>[].obs;

  @override
  void onInit() {
    super.onInit();
    _initializeUser();
  }

  @override
  void onClose() {
    _locationSubscription?.cancel();
    _activityStreamSubscription?.cancel();
    super.onClose();
  }

  void _initializeUser() {
    final user = _auth.currentUser;
    if (user != null) {
      _checkInitialStatus();
      _listenToActivityLogs();
    }
  }

  Future<void> _checkInitialStatus() async {
    final user = _auth.currentUser;
    if (user != null) {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      userName.value = user.displayName ?? userDoc.data()?['name'] ?? user.email ?? "Staff";
      if (userDoc.exists && userDoc.data()!['isClockedIn'] == true) {
        isClockedIn.value = true;
        _startLocationUpdates();
      }
    }
  }

  void _listenToActivityLogs() {
    final user = _auth.currentUser;
    if (user == null) return;

    _activityStreamSubscription?.cancel();
    Query query = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('activity_logs')
        .orderBy('timestamp', descending: true)
        .limit(10);

    _activityStreamSubscription = query.snapshots().listen((snapshot) {
      activityLogs.value = snapshot.docs.map((doc) => ActivityLog.fromFirestore(doc)).toList();
      if (activityLogs.isNotEmpty) {
        final firstLogTimestamp = activityLogs.first.timestamp;
        lastActivityTime.value = DateFormat('hh:mm a').format(firstLogTimestamp.toDate());
      } else {
        lastActivityTime.value = 'N/A';
      }
    });
  }

  void clockIn() async {
    isLoading.value = true;
    await _updateClockInStatus(true);
    _startLocationUpdates();
    isClockedIn.value = true;
    isLoading.value = false;
    Get.snackbar('Success', 'You are now clocked in.', backgroundColor: Colors.green, colorText: Colors.white);
  }

  void clockOut() async {
    isLoading.value = true;
    await _updateClockInStatus(false);
    _locationSubscription?.cancel();
    isClockedIn.value = false;
    isLoading.value = false;
    Get.snackbar('Success', 'You have clocked out.', backgroundColor: Colors.red, colorText: Colors.white);
  }

  void _startLocationUpdates() {
    _locationSubscription?.cancel();
    _locationSubscription = _location.onLocationChanged.listen(
          (LocationData currentLocation) {
        if (isClockedIn.value) {
          _updateLiveLocation(currentLocation);
        }
      },
    );
  }

  Future<void> _updateLiveLocation(LocationData locationData) async {
    final user = _auth.currentUser;
    if (user != null && locationData.latitude != null && locationData.longitude != null) {
      await _firestore.collection('users').doc(user.uid).update({
        'currentLocation': GeoPoint(locationData.latitude!, locationData.longitude!),
        'lastSeen': Timestamp.now(),
      });
    }
  }

  Future<void> _updateClockInStatus(bool status) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final locationData = await _getCurrentLocation();
    if (locationData == null) {
      Get.snackbar("Error", "Could not get location. Please enable GPS.");
      return;
    }

    await _firestore.collection('users').doc(user.uid).update({
      'isClockedIn': status,
      'lastSeen': Timestamp.now(),
      'currentLocation': GeoPoint(locationData.latitude!, locationData.longitude!),
    });

    await _firestore.collection('users').doc(user.uid).collection('activity_logs').add({
      'timestamp': FieldValue.serverTimestamp(),
      'status': status ? 'clock-in' : 'clock-out',
      'location': GeoPoint(locationData.latitude!, locationData.longitude!),
    });
  }

  Future<LocationData?> _getCurrentLocation() async {
    Location location = Location();
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) return null;
    }

    permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return null;
    }

    final currentLoc = await location.getLocation();
    _updateAddress(currentLoc);
    return currentLoc;
  }

  Future<void> _updateAddress(LocationData locationData) async {
    try {
      List<geocoding.Placemark> placemarks =
      await geocoding.placemarkFromCoordinates(
          locationData.latitude!, locationData.longitude!);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        currentAddress.value = "${place.street}, ${place.locality}";
      } else {
        currentAddress.value = "Address not found.";
      }
    } catch (e) {
      currentAddress.value = "Could not get address.";
    }
  }

  Future<void> signOut() async {
    if (isClockedIn.value) {
      clockOut();
    }
    await _auth.signOut();
    Get.offAllNamed(Routes.LOGIN);
  }
}

