import 'package:home_widget/home_widget.dart';
import 'dart:io' show Platform;

class WidgetHelper {
  // Use the fully qualified provider name as declared in AndroidManifest.xml
  static const String androidWidgetProvider =
      'com.example.bagimliss.SavingsWidgetProvider';
  
  // iOS widget identifier
  static const String iOSWidgetName = 'SavingsWidget';
  
  // App Group identifier for iOS
  static const String appGroupId = 'group.com.tasdemir.habitfree';

  static Future<void> updateSavings(String formatted) async {
    try {
      await HomeWidget.saveWidgetData<String>('savings_text', formatted);
      // Trigger widget update on respective platforms
      if (Platform.isAndroid) {
        await HomeWidget.updateWidget(androidName: androidWidgetProvider);
      } else if (Platform.isIOS) {
        await HomeWidget.updateWidget(iOSName: iOSWidgetName);
      }
    } catch (_) {}
  }
  
  // Initialize widget settings
  static Future<void> initialize() async {
    try {
      if (Platform.isIOS) {
        await HomeWidget.setAppGroupId(appGroupId);
      }
    } catch (_) {}
  }
}
