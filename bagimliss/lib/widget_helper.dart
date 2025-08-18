import 'package:home_widget/home_widget.dart';
import 'dart:io' show Platform;

class WidgetHelper {
  // Use the fully qualified provider name as declared in AndroidManifest.xml
  static const String widgetProvider =
      'com.example.bagimliss.SavingsWidgetProvider';

  static Future<void> updateSavings(String formatted) async {
    try {
      await HomeWidget.saveWidgetData<String>('savings_text', formatted);
      // Trigger widget update on respective platforms
      if (Platform.isAndroid) {
        await HomeWidget.updateWidget(androidName: widgetProvider);
      } else {
        await HomeWidget.updateWidget(iOSName: widgetProvider);
      }
    } catch (_) {}
  }
}
