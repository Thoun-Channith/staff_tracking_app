import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  StreamSubscription? _userDocSubscription;

  // --- MAP CONTROLLER ---
  GoogleMapController? mapController;

  // --- OBSERVABLES ---
  var isClockedIn = false.obs;
  var userName = ''.obs;
  var isLoading = true.obs;
  var isButtonLoading = false.obs;
  var currentAddress = 'Getting location...'.obs;
  var lastActivityTime = 'N/A'.obs;
  var dateFilter = 'Last 7 Days'.obs;
  final activityLogs = <ActivityLog>[].obs;

  // --- MAP OBSERVABLES ---
  final markers = <Marker>{}.obs;
  final initialCameraPosition = const CameraPosition(
    target: LatLng(11.5564, 104.9282), // Default to Phnom Penh
    zoom: 14.0,
  ).obs;

  @override
  void onInit() {
    super.onInit();
    _initializeUser();
  }

  @override
  void onClose() {
    _locationSubscription?.cancel();
    _activityStreamSubscription?.cancel();
    _userDocSubscription?.cancel();
    mapController?.dispose();
    super.onClose();
  }

  void onMapCreated(GoogleMapController controller) {
    mapController = controller;
    if (initialCameraPosition.value.target.latitude != 11.5564) {
      mapController?.animateCamera(
          CameraUpdate.newCameraPosition(initialCameraPosition.value)
      );
    }
  }

  void _initializeUser() {
    final user = _auth.currentUser;
    if (user != null) {
      _userDocSubscription = _firestore.collection('users').doc(user.uid).snapshots().listen((doc) async {
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          userName.value = data['name'] ?? user.email ?? 'Staff Member';
          isClockedIn.value = data['isClockedIn'] ?? false;

          if (isClockedIn.value) {
            _startLocationUpdates();
          } else {
            _locationSubscription?.cancel();
          }
        }
        await _getCurrentLocationAndAddress();
        isLoading.value = false;
      });
      _listenToActivityLogs();
    } else {
      isLoading.value = false;
    }
  }

  void setFilter(String newFilter) {
    if (dateFilter.value == newFilter) return;
    dateFilter.value = newFilter;
    _listenToActivityLogs();
  }

  void _listenToActivityLogs() {
    final user = _auth.currentUser;
    if (user == null) return;
    _activityStreamSubscription?.cancel();

    Query query = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('activity_logs')
        .orderBy('timestamp', descending: true);

    if (dateFilter.value == 'Last 7 Days') {
      DateTime sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      query = query.where('timestamp', isGreaterThanOrEqualTo: sevenDaysAgo);
    }

    _activityStreamSubscription = query.snapshots().listen((snapshot) {
      final logs = snapshot.docs.map((doc) => ActivityLog.fromFirestore(doc)).toList();
      for (var log in logs) {
        _fetchAddressForLog(log);
      }
      activityLogs.value = logs;

      if (activityLogs.isNotEmpty) {
        final firstLogTimestamp = activityLogs.first.timestamp;
        if (firstLogTimestamp != null) {
          lastActivityTime.value = DateFormat('hh:mm a').format(firstLogTimestamp.toDate());
        }
      } else {
        lastActivityTime.value = 'N/A';
      }
    });
  }

  Future<void> _fetchAddressForLog(ActivityLog log) async {
    if (log.location == null) {
      log.address.value = "No location data";
      return;
    }
    try {
      List<geocoding.Placemark> placemarks = await geocoding.placemarkFromCoordinates(
          log.location!.latitude, log.location!.longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        log.address.value = "${place.street}, ${place.locality}";
      } else {
        log.address.value = "Address not found.";
      }
    } catch (e) {
      log.address.value = "Could not get address.";
    }
  }

  // --- OPTIMIZED CHECK-IN/OUT ---
  Future<void> toggleCheckInStatus() async {
    isButtonLoading.value = true;

    // Optimistic UI update - happens instantly
    final newStatus = !isClockedIn.value;

    // Perform the slow operations in the background
    _updateClockInStatus(newStatus).then((_) {
      isButtonLoading.value = false;
      Get.snackbar('Success', 'You are now ${newStatus ? "clocked in" : "clocked out"}.');
    }).catchError((error) {
      // If something fails, revert the status and show error
      isButtonLoading.value = false;
      Get.snackbar('Error', 'Action failed. Please try again.');
    });
  }

  void _startLocationUpdates() {
    _locationSubscription?.cancel();
    _locationSubscription = _location.onLocationChanged.listen((LocationData currentLocation) {
      if (isClockedIn.value) {
        _updateLiveLocation(currentLocation);
        _updateMapWithLocation(currentLocation);
      }
    });
  }

  void _updateMapWithLocation(LocationData locationData) {
    if (locationData.latitude == null || locationData.longitude == null) return;
    final newPosition = LatLng(locationData.latitude!, locationData.longitude!);
    mapController?.animateCamera(CameraUpdate.newLatLng(newPosition));
    markers.value = {
      Marker(
          markerId: const MarkerId("currentLocation"),
          position: newPosition,
          infoWindow: const InfoWindow(title: "My Current Location")
      )
    };
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
      // Re-throw an error to be caught by the calling function
      throw Exception("Could not get location. Please enable GPS.");
    }
    await _firestore.collection('users').doc(user.uid).update({
      'isClockedIn': status,
      'lastSeen': Timestamp.now(),
      'currentLocation': GeoPoint(locationData.latitude!, locationData.longitude!),
    });
    await _firestore.collection('users').doc(user.uid).collection('activity_logs').add({
      'timestamp': FieldValue.serverTimestamp(),
      'status': status ? 'checked-in' : 'checked-out',
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
    return await location.getLocation();
  }

  Future<void> _getCurrentLocationAndAddress() async {
    try {
      LocationData? locationData = await _getCurrentLocation();
      if (locationData != null && locationData.latitude != null && locationData.longitude != null) {
        initialCameraPosition.value = CameraPosition(
          target: LatLng(locationData.latitude!, locationData.longitude!),
          zoom: 16.0,
        );
        _updateMapWithLocation(locationData);

        List<geocoding.Placemark> placemarks = await geocoding.placemarkFromCoordinates(locationData.latitude!, locationData.longitude!);
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          currentAddress.value = "${place.street}, ${place.locality}";
        } else {
          currentAddress.value = "Address not found.";
        }
      }
    } catch (e) {
      currentAddress.value = "Could not get location.";
    }
  }

  Future<void> signOut() async {
    if (isClockedIn.value) {
      await _updateClockInStatus(false);
    }
    await _auth.signOut();
    Get.offAllNamed(Routes.LOGIN);
  }
}

