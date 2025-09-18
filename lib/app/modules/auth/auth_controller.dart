import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../routes/app_pages.dart';

class AuthController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  var isPasswordHidden = true.obs;
  var isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    _setupNotificationListeners();
  }

  // This handles notifications that arrive while the app is OPEN.
  void _setupNotificationListeners() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        Get.snackbar(
          message.notification!.title ?? 'Notification',
          message.notification!.body ?? '',
          snackPosition: SnackPosition.TOP,
        );
      }
    });
  }

  // This gets permission and saves the device token.
  Future<void> _initializeNotifications(String userId) async {
    await _fcm.requestPermission();
    final fcmToken = await _fcm.getToken();
    if (fcmToken != null) {
      await _firestore.collection('users').doc(userId).update({
        'fcmToken': fcmToken,
      });
    }
  }

  void togglePasswordVisibility() {
    isPasswordHidden.value = !isPasswordHidden.value;
  }

  Future<void> createUser() async {
    // ... (your existing validation logic)
    isLoading.value = true;
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
      final user = userCredential.user;
      if (user != null) {
        await user.updateDisplayName(nameController.text.trim());
        await _firestore.collection('users').doc(user.uid).set({
          'name': nameController.text.trim(),
          'email': emailController.text.trim(),
          'uid': user.uid,
          'isCheckedIn': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await _initializeNotifications(user.uid); // Run after signup
      }
    } on FirebaseAuthException catch (e) {
      Get.snackbar('Sign Up Failed', e.message ?? 'An unknown error occurred.');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> login() async {
    // ... (your existing validation logic)
    isLoading.value = true;
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
      final user = userCredential.user;
      if (user != null) {
        await _initializeNotifications(user.uid); // Run after login
      }
    } on FirebaseAuthException catch (e) {
      Get.snackbar('Login Failed', e.message ?? 'An unknown error occurred.');
    } finally {
      isLoading.value = false;
    }
  }
}