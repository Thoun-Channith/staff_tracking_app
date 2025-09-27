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
import 'package:collection/collection.dart';

class HomeController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Location _location = Location();

  // --- NEW: TIMER FOR BACKGROUND TRACKING ---
  Timer? _locationTimer;

  StreamSubscription<LocationData>? _locationSubscription;
  StreamSubscription? _activityStreamSubscription;
  StreamSubscription? _userDocSubscription;

  GoogleMapController? mapController;
  var isClockedIn = false.obs;
  var userName = ''.obs;
  var isLoading = true.obs;
  var isButtonLoading = false.obs;
  var currentAddress = 'Getting location...'.obs;
  var lastActivityTime = 'N/A'.obs;
  var dateFilter = 'Last 7 Days'.obs;
  final activityLogs = <ActivityLog>[].obs;
  final markers = <Marker>{}.obs;
  final initialCameraPosition = const CameraPosition(
    target: LatLng(13.3614, 103.8603),
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
    // --- NEW: CANCEL TIMER ON CLOSE ---
    _locationTimer?.cancel();
    mapController?.dispose();
    super.onClose();
  }

  void onMapCreated(GoogleMapController controller) {
    mapController = controller;
    if (initialCameraPosition.value.target.latitude != 13.3614) {
      mapController?.animateCamera(
          CameraUpdate.newCameraPosition(initialCameraPosition.value));
    }
  }

  void _initializeUser() {
    final user = _auth.currentUser;
    if (user != null) {
      _userDocSubscription =
          _firestore.collection('users').doc(user.uid).snapshots().listen((
              doc,
              ) async {
            if (doc.exists && doc.data() != null) {
              final data = doc.data()!;
              userName.value = data['name'] ?? user.email ?? 'Staff Member';
              isClockedIn.value = data['isClockedIn'] ?? false;

              if (isClockedIn.value) {
                _startLocationUpdates();
              } else {
                _stopLocationUpdates();
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
      final logs =
      snapshot.docs.map((doc) => ActivityLog.fromFirestore(doc)).toList();
      for (var log in logs) {
        _fetchAddressForLog(log);
      }
      activityLogs.value = logs;
      final lastLog =
      activityLogs.firstWhereOrNull((log) => log.timestamp != null);
      if (lastLog != null && lastLog.timestamp != null) {
        lastActivityTime.value =
            DateFormat('hh:mm a').format(lastLog.timestamp!.toDate());
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
      List<geocoding.Placemark> placemarks =
      await geocoding.placemarkFromCoordinates(
        log.location!.latitude,
        log.location!.longitude,
      );
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

  Future<void> toggleCheckInStatus() async {
    isButtonLoading.value = true;
    try {
      final newStatus = !isClockedIn.value;
      await _updateClockInStatus(newStatus);
      Get.snackbar(
        'Success',
        'You are now ${newStatus ? "clocked in" : "clocked out"}.',
      );
    } catch (e) {
      Get.snackbar('Error', 'Action failed: ${e.toString()}');
    } finally {
      isButtonLoading.value = false;
    }
  }

  // --- REVISED TO MANAGE THE TIMER ---
  void _startLocationUpdates() {
    // Start live tracking for the map
    _locationSubscription?.cancel();
    _locationSubscription =
        _location.onLocationChanged.listen((LocationData currentLocation) {
          _updateMapWithLocation(currentLocation);
        });

    // Start the 5-minute timer for background history
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _saveLocationToHistory();
    });
  }

  // --- NEW: FUNCTION TO STOP ALL TRACKING ---
  void _stopLocationUpdates() {
    _locationSubscription?.cancel();
    _locationTimer?.cancel();
  }

  // --- NEW: FUNCTION TO SAVE LOCATION HISTORY ---
  Future<void> _saveLocationToHistory() async {
    final user = _auth.currentUser;
    if (user == null || !isClockedIn.value) return;

    try {
      final locationData = await _getCurrentLocation();
      if (locationData != null &&
          locationData.latitude != null &&
          locationData.longitude != null) {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('locations')
            .add({
          'timestamp': FieldValue.serverTimestamp(),
          'location':
          GeoPoint(locationData.latitude!, locationData.longitude!),
        });
      }
    } catch (e) {
      // You might want to log this error silently
      print("Failed to save background location: $e");
    }
  }

  void _updateMapWithLocation(LocationData locationData) {
    if (locationData.latitude == null || locationData.longitude == null) return;
    final newPosition =
    LatLng(locationData.latitude!, locationData.longitude!);
    mapController?.animateCamera(CameraUpdate.newLatLng(newPosition));
    markers.value = {
      Marker(
        markerId: const MarkerId("currentLocation"),
        position: newPosition,
        infoWindow: const InfoWindow(title: "My Current Location"),
      )
    };
  }

  Future<void> _updateClockInStatus(bool status) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not found");
    final locationData = await _getCurrentLocation();
    if (locationData == null ||
        locationData.latitude == null ||
        locationData.longitude == null) {
      throw Exception("Could not get location. Please enable GPS.");
    }
    final userDocRef = _firestore.collection('users').doc(user.uid);
    final activityLogRef = userDocRef.collection('activity_logs').doc();
    final WriteBatch batch = _firestore.batch();
    batch.update(userDocRef, {
      'isClockedIn': status,
      'lastSeen': Timestamp.now(),
      'currentLocation':
      GeoPoint(locationData.latitude!, locationData.longitude!),
    });
    batch.set(activityLogRef, {
      'timestamp': FieldValue.serverTimestamp(),
      'status': status ? 'checked-in' : 'checked-out',
      'location': GeoPoint(locationData.latitude!, locationData.longitude!),
    });
    await batch.commit();
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
      if (locationData != null &&
          locationData.latitude != null &&
          locationData.longitude != null) {
        initialCameraPosition.value = CameraPosition(
          target: LatLng(locationData.latitude!, locationData.longitude!),
          zoom: 16.0,
        );
        _updateMapWithLocation(locationData);
        List<geocoding.Placemark> placemarks =
        await geocoding.placemarkFromCoordinates(
          locationData.latitude!,
          locationData.longitude!,
        );
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