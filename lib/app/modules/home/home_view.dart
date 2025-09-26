import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:staff_tracking_app/app/modules/home/home_controller.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Dashboard'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => controller.signOut(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWelcomeCard(),
            const SizedBox(height: 24),
            _buildActionCard(),
            const SizedBox(height: 24),
            _buildRecentActivitySection(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 30,
              backgroundColor: Colors.blueAccent,
              child: Icon(Icons.person, size: 30, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Welcome back,",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  Obx(() => Text(
                    controller.userName.value,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // THIS IS THE FIXED ROW
            Row(
              children: [
                Expanded(child: _buildInfoColumn("Last Activity", controller.lastActivityTime)),
                Expanded(child: _buildInfoColumn("Status", controller.isClockedIn)),
              ],
            ),
            const SizedBox(height: 20),
            Obx(() => Text(
              controller.currentAddress.value,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.blueGrey),
            )),
            const SizedBox(height: 20),
            Obx(() => controller.isLoading.value
                ? const CircularProgressIndicator()
                : SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: controller.isClockedIn.value
                    ? () => controller.clockOut()
                    : () => controller.clockIn(),
                icon: Icon(controller.isClockedIn.value ? Icons.logout : Icons.login),
                label: Text(
                  controller.isClockedIn.value ? 'Clock Out' : 'Clock In',
                  style: const TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: controller.isClockedIn.value ? Colors.redAccent : Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  // THIS WIDGET IS FIXED to be reactive
  Widget _buildInfoColumn(String title, Rx<dynamic> value) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.grey, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Obx(() {
          // Handle boolean status explicitly
          if (value.value is bool) {
            return Text(
              value.value ? "Clocked In" : "Clocked Out",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            );
          }
          return Text(
            value.value.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          );
        }),
      ],
    );
  }

  Widget _buildRecentActivitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Recent Activity",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        // THIS Obx WRAPPER FIXES THE REAL-TIME UPDATE
        Obx(() {
          if (controller.activityLogs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Text("No recent activity found.", style: TextStyle(color: Colors.grey)),
              ),
            );
          }
          return ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: controller.activityLogs.length,
            itemBuilder: (context, index) {
              final log = controller.activityLogs[index];
              final isClockIn = log.status == 'clock-in';
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: Icon(
                    isClockIn ? Icons.login : Icons.logout,
                    color: isClockIn ? Colors.green : Colors.red,
                  ),
                  title: Text(
                    isClockIn ? "Clocked In" : "Clocked Out",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(DateFormat('MMM d, yyyy').format(log.timestamp.toDate())),
                  trailing: Text(DateFormat('hh:mm a').format(log.timestamp.toDate())),
                ),
              );
            },
          );
        }),
      ],
    );
  }
}

