import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:staff_tracking_app/app/modules/home/home_controller.dart';
import 'package:staff_tracking_app/app/models/activity_log_model.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () => controller.signOut(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Obx(() => controller.isLoading.value
                  ? _buildLoadingIndicator()
                  : _buildWelcomeCard(theme)),
              const SizedBox(height: 20),
              _buildMapView(),
              const SizedBox(height: 20),
              _buildCheckInButton(),
              const SizedBox(height: 24),
              _buildActivityHeader(theme),
              const SizedBox(height: 8),
              _buildRecentActivityList(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapView() {
    return SizedBox(
      height: 250,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: Obx(
              () => GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: controller.initialCameraPosition.value,
            onMapCreated: controller.onMapCreated,
            markers: Set<Marker>.of(controller.markers),
            myLocationButtonEnabled: false,
            myLocationEnabled: false,
            // --- FIXES ARE HERE ---
            zoomControlsEnabled: true, // Show the + and - buttons
            zoomGesturesEnabled: true, // Allow pinch-to-zoom
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Card(
      child: SizedBox(
        height: 180,
        child: Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard(ThemeData theme) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Obx(() => Text(
              'Welcome, ${controller.userName.value}',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            )),
            const SizedBox(height: 16),
            _buildInfoRow(
              theme,
              icon: Icons.location_on_outlined,
              label: 'Location:',
              valueWidget: Obx(() => Text(
                controller.currentAddress.value,
                style: theme.textTheme.bodyLarge,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              )),
            ),
            const SizedBox(height: 8),
            Obx(
                  () => _buildInfoRow(
                theme,
                icon: controller.isClockedIn.value
                    ? Icons.check_circle_outline
                    : Icons.cancel_outlined,
                iconColor:
                controller.isClockedIn.value ? Colors.green : Colors.grey,
                label: 'Status:',
                valueText:
                controller.isClockedIn.value ? 'Checked In' : 'Checked Out',
              ),
            ),
            const SizedBox(height: 8),
            Obx(
                  () => _buildInfoRow(
                theme,
                icon: Icons.access_time_outlined,
                label: 'Last Activity:',
                valueText: controller.lastActivityTime.value,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme,
      {required IconData icon,
        required String label,
        String? valueText,
        Widget? valueWidget,
        Color? iconColor}) {
    return Row(
      children: [
        Icon(icon, color: iconColor ?? theme.colorScheme.secondary, size: 20),
        const SizedBox(width: 12),
        Text('$label ',
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        Expanded(
          child: valueWidget ??
              Text(
                valueText ?? '',
                style: theme.textTheme.bodyLarge,
              ),
        ),
      ],
    );
  }

  Widget _buildCheckInButton() {
    return Obx(
          () => ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: controller.isClockedIn.value
              ? Colors.orange.shade700
              : Colors.green.shade600,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        onPressed: controller.isButtonLoading.value
            ? null
            : () => controller.toggleCheckInStatus(),
        icon: controller.isButtonLoading.value
            ? Container(
          width: 24,
          height: 24,
          padding: const EdgeInsets.all(2.0),
          child: const CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 3,
          ),
        )
            : Icon(
            controller.isClockedIn.value ? Icons.logout : Icons.login),
        label: Text(
            controller.isClockedIn.value ? 'Check Out' : 'Check In'),
      ),
    );
  }

  Widget _buildActivityHeader(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Recent Activity',
          style: theme.textTheme.titleLarge,
        ),
        Obx(() => PopupMenuButton<String>(
          onSelected: (value) => controller.setFilter(value),
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
              value: 'Last 7 Days',
              child: Text('Last 7 Days'),
            ),
            const PopupMenuItem<String>(
              value: 'All Time',
              child: Text('All Time'),
            ),
          ],
          child: Row(
            children: [
              Text(
                controller.dateFilter.value,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.secondary),
              ),
              Icon(Icons.arrow_drop_down,
                  color: theme.colorScheme.secondary),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildRecentActivityList(ThemeData theme) {
    return Obx(() {
      if (controller.activityLogs.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Text(
              'No activity found for "${controller.dateFilter.value}".',
            ),
          ),
        );
      }
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: controller.activityLogs.length,
        itemBuilder: (context, index) {
          final ActivityLog log = controller.activityLogs[index];
          final isCheckIn = log.status == 'checked-in';

          final formattedTime = log.timestamp != null
              ? DateFormat('EEE, MMM d, hh:mm a').format(log.timestamp!.toDate())
              : 'No timestamp';

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: Icon(
                isCheckIn ? Icons.login : Icons.logout,
                color: isCheckIn ? Colors.green : Colors.orange,
              ),
              title: Text(isCheckIn ? 'Checked In' : 'Checked Out'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formattedTime),
                  const SizedBox(height: 4),
                  Obx(
                        () => Row(
                      children: [
                        Icon(Icons.location_on,
                            size: 14,
                            color: theme.textTheme.bodySmall?.color),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            log.address.value,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }
}