import 'package:get/get.dart';
import 'package:staff_tracking_app/app/modules/auth/auth_binding.dart';
import 'package:staff_tracking_app/app/modules/auth/login_view.dart';
import 'package:staff_tracking_app/app/modules/home/home_binding.dart';
import 'package:staff_tracking_app/app/modules/home/home_view.dart';
import 'package:staff_tracking_app/app/modules/splash/splash_binding.dart';
import 'package:staff_tracking_app/app/modules/splash/splash_view.dart';

part 'app_routes.dart';

class AppPages {
  static const INITIAL = Routes.SPLASH;

  static final routes = [
    GetPage(
      name: Routes.SPLASH,
      page: () => const SplashView(),
      binding: SplashBinding(),
    ),
    GetPage(
      name: Routes.LOGIN,
      page: () => LoginView(),
      binding: AuthBinding(),
    ),
    GetPage(
      name: Routes.HOME,
      page: () => HomeView(),
      binding: HomeBinding(),
    ),
  ];

}