import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter;
import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';
// Charts removed per request; no fl_chart import
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:workmanager/workmanager.dart';
import 'widget_helper.dart';
import 'notification_helper.dart';

const String kWidgetUpdateTask = 'widget_update_task';
// Workmanager init flag to avoid duplicate initialize on hot reload
bool _wmDidInit = false;

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Arkaplanda pluginleri kaydet
      WidgetsFlutterBinding.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      final qt = prefs.getString('quitTime');
      final dc = prefs.getDouble('dailyCost');
      final da = prefs.getDouble('dailyAmount');
      final gt = prefs.getDouble('goalTarget');
      final goalNotified = prefs.getBool('goalNotified') ?? false;
      if (qt == null || dc == null || da == null) return Future.value(true);
      final quit = DateTime.tryParse(qt);
      if (quit == null) return Future.value(true);
      final seconds = DateTime.now().difference(quit).inSeconds;
      final saved = (dc * da) * (seconds / 86400.0);
      final f = NumberFormat.currency(
        locale: 'tr_TR',
        symbol: 'TL',
        decimalDigits: 2,
      );
      await WidgetHelper.updateSavings(f.format(saved));

      // Hedefe ulaşıldıysa bir kez bildirim gönder
      if (gt != null && saved >= gt && !goalNotified) {
        await NotificationHelper.showSimple(
          1001,
          'Hedefe Ulaştın! 🎉',
          'Tasarruf hedefinize ulaştınız. Harikasınız!',
        );
        await prefs.setBool('goalNotified', true);
      }
    } catch (_) {}
    return Future.value(true);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationHelper.initialize();
  await NotificationHelper.requestPermission();
  await _setupWorkmanagerIfAndroid();
  runApp(const MyApp());
}

Future<void> _setupWorkmanagerIfAndroid() async {
  if (!Platform.isAndroid) return;
  const uniqueName = 'periodic_widget_update';
  // Try initialize + register with retries to handle race conditions during reload/restart.
  for (var attempt = 1; attempt <= 5; attempt++) {
    try {
      if (!_wmDidInit) {
        await Workmanager().initialize(
          callbackDispatcher,
          isInDebugMode: kDebugMode,
        );
        _wmDidInit = true;
        // Give a short moment for the platform channel to be fully ready.
        await Future.delayed(const Duration(milliseconds: 250));
      }
      await Workmanager().registerPeriodicTask(
        uniqueName,
        kWidgetUpdateTask,
        frequency: const Duration(minutes: 30),
        initialDelay: const Duration(minutes: 5),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.notRequired),
      );
      break; // success
    } catch (e) {
      // If initialize complaint, wait a moment and retry
      if (e is PlatformException &&
          (e.message?.contains('initialized') ?? false)) {
        // Try to (re)initialize once more before next retry
        _wmDidInit = false;
      }
      if (attempt == 5) {
        // Don't crash the app on reload; just stop retrying.
        debugPrint('Workmanager setup failed after retries: $e');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 600));
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bağımlılık Tasarruf Takip',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6D5DF6),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          scrolledUnderElevation: 0,
        ),
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      home: const MyHomePage(title: 'Bağımlılık Tasarruf Takip'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  DateTime? quitTime;
  double? dailyCost;
  double? dailyAmount;
  Timer? _ticker;
  double? goalTarget; // Kullanıcının hedeflediği tasarruf miktarı (TL)
  DateTime? _lastWidgetPush;
  bool _riskRemindersOn = false; // Yüksek risk saat uyarıları
  // Yeni: Birim ölçü sistemi (uzunluk odaklı)
  String _unitName = 'sigara dalı';
  double _unitLengthCm = 8.4; // birim başına uzunluk (cm)
  int? _packSize =
      20; // opsiyonel paket boyutu (ör: 20 sigara). null => hesaplanmaz
  double get totalSaved {
    if (quitTime == null || dailyCost == null || dailyAmount == null) return 0;
    final seconds = DateTime.now().difference(quitTime!).inSeconds;
    final nonNegSeconds = seconds < 0 ? 0 : seconds;
    return (dailyCost! * dailyAmount!) * (nonNegSeconds / 86400.0);
  }

  double get _dailyRate =>
      (dailyCost ?? 0) * (dailyAmount ?? 0); // günde tasarruf edilen tutar

  double? get _daysToGoal {
    if (goalTarget == null) return null;
    if (_dailyRate <= 0) return double.infinity;
    final remaining = (goalTarget! - totalSaved);
    if (remaining <= 0) return 0;
    return remaining / _dailyRate; // gün
  }

  // Ek metrikler (grafiksiz gösterim)
  double get _totalAvoidedUnits {
    if (quitTime == null || dailyAmount == null) return 0;
    final seconds = DateTime.now().difference(quitTime!).inSeconds;
    final nonNegSeconds = seconds < 0 ? 0 : seconds;
    return (dailyAmount! * (nonNegSeconds / 86400.0));
  }

  String? get _etaDateText {
    final d = _daysToGoal;
    if (d == null || d == double.infinity) return null;
    if (d <= 0) return _formatDate(DateTime.now());
    final eta = DateTime.now().add(Duration(seconds: (d * 86400).ceil()));
    return _formatDate(eta);
  }

  // Yeni: Toplam birim ve uzunluk karşılaştırmaları (kesirleri koru)
  double get _totalUnitsExact => _totalAvoidedUnits;
  double get _totalMeters => (_totalUnitsExact * _unitLengthCm) / 100.0;
  double? get _packsCount =>
      _packSize != null && _packSize! > 0
          ? _totalUnitsExact / _packSize!
          : null;

  // Tahmini yaşam süresi kazanımı (sigara için literatürde ~11 dk/birim)
  static const double _lostMinutesPerUnit = 11.0; // dakika/birim
  double get _lifeGainedMinutes => _totalUnitsExact * _lostMinutesPerUnit;

  String get _lifeGainedHumanReadable {
    final mins = _lifeGainedMinutes;
    if (mins < 60) {
      return '+${mins.toStringAsFixed(0)} dakika';
    }
    final hours = mins / 60.0;
    if (hours < 24) {
      return '+${hours.toStringAsFixed(1)} saat';
    }
    final days = hours / 24.0;
    return '+${days.toStringAsFixed(days < 10 ? 1 : 0)} gün';
  }

  void _showUnitMeasureDialog() {
    final nameCtrl = TextEditingController(text: _unitName);
    final lenCtrl = TextEditingController(
      text: _unitLengthCm.toStringAsFixed(1),
    );
    final packCtrl = TextEditingController(
      text: _packSize == null ? '' : _packSize!.toString(),
    );
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Birim ölçüsü (uzunluk)'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Birim adı',
                        hintText: 'Örn: sigara dalı',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: lenCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Birim uzunluğu (cm)',
                        hintText: 'Örn: 8.4',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: packCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Paket boyutu (opsiyonel)',
                        hintText: 'Örn: 20 (boş bırakılabilir)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            contentPadding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 0),
            actionsPadding: const EdgeInsets.fromLTRB(24.0, 0, 24.0, 24.0),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('İptal'),
              ),
              TextButton(
                onPressed: () {
                  final name =
                      nameCtrl.text.trim().isEmpty
                          ? 'birim'
                          : nameCtrl.text.trim();
                  final lenRaw = lenCtrl.text.trim().replaceAll(',', '.');
                  final lenVal = double.tryParse(lenRaw);
                  if (lenVal == null || lenVal <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Geçerli bir uzunluk (cm) girin.'),
                      ),
                    );
                    return;
                  }
                  int? pack;
                  if (packCtrl.text.trim().isNotEmpty) {
                    pack = int.tryParse(packCtrl.text.trim());
                    if (pack == null || pack <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Paket boyutu sayı olmalı.'),
                        ),
                      );
                      return;
                    }
                  }
                  setState(() {
                    _unitName = name;
                    _unitLengthCm = lenVal;
                    _packSize = pack;
                  });
                  _persistUnitMeasure();
                  Navigator.of(context).pop();
                },
                child: const Text('Kaydet'),
              ),
            ],
          ),
    );
  }

  // Para formatlama (TL)
  String _money(double value, {int decimals = 2}) {
    final f = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: 'TL',
      decimalDigits: decimals,
    );
    // Intl TL simgesini sonda gösteriyor, biz başa almak istersek değiştirebiliriz
    // Ancak Türkiye'de genelde TL sonda kullanılır: 1.234,56 TL
    return f.format(value);
  }

  void _clearGoal() {
    setState(() {
      goalTarget = null;
    });
    _persistState();
  }

  final List<String> _motivationMessages = [
    'Her saniye kendin için büyük bir adım atıyorsun! Vazgeçme!',
    'Kriz anı geçici, kazancın kalıcı! Dayan, güçlüsün!',
    'Bugün de kendin için en iyisini yapıyorsun.',
    'Sen kafana koyduğunu yapamayacak biri misin? Hadi göster!',
  ];

  void _showMotivationDialog() {
    final msg =
        _motivationMessages[DateTime.now().millisecond %
            _motivationMessages.length];
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Motivasyon'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Teşekkürler'),
              ),
            ],
          ),
    );
  }

  void _showInputDialog() {
    final quitTimeController = TextEditingController();
    final costController = TextEditingController();
    final amountController = TextEditingController();
    // Varsayılan tarih (mevcut kayıt varsa onu göster)
    quitTimeController.text = _formatDate(quitTime ?? DateTime.now());
    // Saat alanı
    final timeController = TextEditingController(
      text: _formatTime(TimeOfDay.fromDateTime(quitTime ?? DateTime.now())),
    );

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Bağımlılık Bilgileri'),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6D5DF6), Color(0xFF46C2CB)],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              const SizedBox(height: 20),
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    children: [
                                      TextField(
                                        controller: quitTimeController,
                                        readOnly: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Bırakma Tarihi',
                                          hintText:
                                              'Takvimden seçmek için dokun',
                                          suffixIcon: Icon(
                                            Icons.calendar_today,
                                          ),
                                          border: OutlineInputBorder(),
                                        ),
                                        onTap: () async {
                                          FocusScope.of(
                                            context,
                                          ).requestFocus(FocusNode());
                                          final now = DateTime.now();
                                          final initial = quitTime ?? now;
                                          final picked = await showDatePicker(
                                            context: context,
                                            initialDate:
                                                initial.isAfter(now)
                                                    ? now
                                                    : initial,
                                            firstDate: DateTime(now.year - 50),
                                            lastDate: now,
                                            helpText: 'Bırakma Tarihini Seç',
                                            cancelText: 'İptal',
                                            confirmText: 'Seç',
                                          );
                                          if (picked != null) {
                                            quitTimeController
                                                .text = _formatDate(picked);
                                          }
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      TextField(
                                        controller: timeController,
                                        readOnly: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Saat',
                                          hintText: 'Saat seçmek için dokun',
                                          suffixIcon: Icon(Icons.access_time),
                                          border: OutlineInputBorder(),
                                        ),
                                        onTap: () async {
                                          FocusScope.of(
                                            context,
                                          ).requestFocus(FocusNode());
                                          final initial =
                                              TimeOfDay.fromDateTime(
                                                quitTime ?? DateTime.now(),
                                              );
                                          final picked = await showTimePicker(
                                            context: context,
                                            initialTime: initial,
                                            helpText: 'Saati Seç',
                                            cancelText: 'İptal',
                                            confirmText: 'Seç',
                                          );
                                          if (picked != null) {
                                            timeController.text = _formatTime(
                                              picked,
                                            );
                                          }
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      TextField(
                                        controller: costController,
                                        decoration: const InputDecoration(
                                          labelText: 'Günlük Maliyet (TL)',
                                          border: OutlineInputBorder(),
                                        ),
                                        keyboardType: TextInputType.number,
                                      ),
                                      const SizedBox(height: 16),
                                      TextField(
                                        controller: amountController,
                                        decoration: const InputDecoration(
                                          labelText: 'Günlük Miktar',
                                          border: OutlineInputBorder(),
                                        ),
                                        keyboardType: TextInputType.number,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('İptal'),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    final parsedCost = double.tryParse(
                                      costController.text.trim().replaceAll(
                                        ',',
                                        '.',
                                      ),
                                    );
                                    final parsedAmount = double.tryParse(
                                      amountController.text.trim().replaceAll(
                                        ',',
                                        '.',
                                      ),
                                    );
                                    if (parsedCost == null ||
                                        parsedAmount == null) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Önce maliyet ve miktarı girin (örn: 60 ve 1 veya 0,5).',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    setState(() {
                                      quitTime = DateTime.now();
                                      dailyCost = parsedCost;
                                      dailyAmount = parsedAmount;
                                    });
                                    _startTicker();
                                    _persistState();
                                    Navigator.of(context).pop();
                                  },
                                  child: const Text('Şu an'),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    final parsedDate = _parseDateFlexible(
                                      quitTimeController.text.trim(),
                                    );
                                    final parsedTime = _parseTimeFlexible(
                                      timeController.text.trim(),
                                    );
                                    final parsedCost = double.tryParse(
                                      costController.text.trim().replaceAll(
                                        ',',
                                        '.',
                                      ),
                                    );
                                    final parsedAmount = double.tryParse(
                                      amountController.text.trim().replaceAll(
                                        ',',
                                        '.',
                                      ),
                                    );

                                    if (parsedDate == null) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Tarih formatı geçersiz. Örn: 16.08.2025 veya 2025-08-16',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    if (parsedTime == null) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Saat formatı geçersiz. Örn: 14:30',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    if (parsedCost == null ||
                                        parsedAmount == null) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Maliyet ve miktar sayı olmalı. Örn: 60 veya 0,5',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    final combined = DateTime(
                                      parsedDate.year,
                                      parsedDate.month,
                                      parsedDate.day,
                                      parsedTime.hour,
                                      parsedTime.minute,
                                    );
                                    setState(() {
                                      quitTime = combined;
                                      dailyCost = parsedCost;
                                      dailyAmount = parsedAmount;
                                    });
                                    _startTicker();
                                    _persistState();
                                    Navigator.of(context).pop();
                                  },
                                  child: const Text('Kaydet'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showGoalDialog() {
    final controller = TextEditingController(
      text: goalTarget == null ? '' : goalTarget!.toStringAsFixed(0),
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hedef Miktar (TL)'),
          content: SizedBox(
            width: double.maxFinite,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Örn: 2000'),
            ),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 0),
          actionsPadding: const EdgeInsets.fromLTRB(24.0, 0, 24.0, 24.0),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () {
                final raw = controller.text.trim();
                if (raw.isEmpty) {
                  setState(() => goalTarget = null);
                  _persistState();
                  Navigator.of(context).pop();
                  return;
                }
                final parsed = double.tryParse(raw.replaceAll(',', '.'));
                if (parsed == null || parsed <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Geçerli bir hedef girin.')),
                  );
                  return;
                }
                setState(() => goalTarget = parsed);
                _persistState();
                // Hedef değiştiyse bildirim bayrağını sıfırla ki tekrar tetiklenebilsin
                SharedPreferences.getInstance().then((prefs) {
                  prefs.remove('goalNotified');
                });
                Navigator.of(context).pop();
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
  }

  // Esnek tarih ayrıştırma: dd.MM.yyyy, dd/MM/yyyy, dd-MM-yyyy, yyyy-MM-dd, yyyy/MM/dd
  DateTime? _parseDateFlexible(String input) {
    if (input.isEmpty) return null;
    // Doğrudan ISO denenir
    final iso = DateTime.tryParse(input);
    if (iso != null) return iso;
    final parts = input.split(RegExp(r"[./-]"));
    if (parts.length != 3) return null;
    int? p0 = int.tryParse(parts[0]);
    int? p1 = int.tryParse(parts[1]);
    int? p2 = int.tryParse(parts[2]);
    if (p0 == null || p1 == null || p2 == null) return null;
    int year, month, day;
    if (parts[0].length == 4) {
      // yyyy-MM-dd
      year = p0;
      month = p1;
      day = p2;
    } else {
      // dd.MM.yyyy
      day = p0;
      month = p1;
      year = p2;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString();
    return '$d.$m.$y';
  }

  String _formatTime(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final min = time.minute.toString().padLeft(2, '0');
    return '$h:$min';
  }

  TimeOfDay? _parseTimeFlexible(String input) {
    if (input.isEmpty) return null;
    final parts = input.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (quitTime != null) {
        setState(() {});
        // Update home screen widget text, throttled to once every 30s
        final now = DateTime.now();
        if (_lastWidgetPush == null ||
            now.difference(_lastWidgetPush!).inSeconds >= 30) {
          _lastWidgetPush = now;
          // Write value first so provider reads fresh data
          WidgetHelper.updateSavings(_money(totalSaved, decimals: 2));
        }
        _checkGoalNotification();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _restoreState();
    _startTicker();
    // Push a refresh when the widget resumes to keep the home widget in sync
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetHelper.updateSavings(_money(totalSaved, decimals: 2));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _restoreState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final qt = prefs.getString('quitTime');
      final dc = prefs.getDouble('dailyCost');
      final da = prefs.getDouble('dailyAmount');
      final gt = prefs.getDouble('goalTarget');
      final len = prefs.getDouble('cigLengthCm'); // geriye dönük uyumluluk
      final unitLen = prefs.getDouble('unitLengthCm');
      final unitName = prefs.getString('unitName');
      final pack = prefs.getInt('packSize');
      final riskOn = prefs.getBool('riskRemindersOn') ?? false;
      if (qt != null && dc != null && da != null) {
        final parsed = DateTime.tryParse(qt);
        if (parsed != null) {
          setState(() {
            quitTime = parsed;
            dailyCost = dc;
            dailyAmount = da;
            goalTarget = gt;
            // Öncelik yeni anahtarlar, yoksa eski cigLengthCm
            if (unitLen != null && unitLen > 0) {
              _unitLengthCm = unitLen;
            } else if (len != null && len > 0) {
              _unitLengthCm = len;
            }
            if (unitName != null && unitName.isNotEmpty) {
              _unitName = unitName;
            }
            if (pack != null && pack > 0) {
              _packSize = pack;
            } else {
              _packSize = null;
            }
            _riskRemindersOn = riskOn;
          });
          // Ensure widget displays the restored savings value
          WidgetHelper.updateSavings(_money(totalSaved, decimals: 2));
        }
      } else {
        // Bileşen yoksa da ölçüyü geri yükle
        if (unitLen != null && unitLen > 0) {
          setState(() => _unitLengthCm = unitLen);
        } else if (len != null && len > 0) {
          setState(() => _unitLengthCm = len);
        }
        if (unitName != null && unitName.isNotEmpty) {
          setState(() => _unitName = unitName);
        }
        if (pack != null && pack > 0) {
          setState(() => _packSize = pack);
        }
        setState(() => _riskRemindersOn = riskOn);
      }
    } on MissingPluginException {
      // Hot reload esnasında plugin henüz hazır olmayabilir; sessizce geç.
    } catch (_) {
      // Geri yükleme sorunları göz ardı edilir.
    }
  }

  Future<void> _persistState() async {
    if (quitTime == null || dailyCost == null || dailyAmount == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('quitTime', quitTime!.toIso8601String());
      await prefs.setDouble('dailyCost', dailyCost!);
      await prefs.setDouble('dailyAmount', dailyAmount!);
      if (goalTarget != null) {
        await prefs.setDouble('goalTarget', goalTarget!);
      } else {
        await prefs.remove('goalTarget');
        await prefs.remove('goalNotified');
      }
      await prefs.setDouble('unitLengthCm', _unitLengthCm);
      await prefs.setString('unitName', _unitName);
      if (_packSize != null && _packSize! > 0) {
        await prefs.setInt('packSize', _packSize!);
      } else {
        await prefs.remove('packSize');
      }
      // Also push the current savings to the widget
      WidgetHelper.updateSavings(_money(totalSaved, decimals: 2));
    } on MissingPluginException {
      // Hot reload esnasında oluşabilir; bir sonraki açılışta yazılacaktır.
    } catch (_) {}
  }

  Future<void> _checkGoalNotification() async {
    if (goalTarget == null) return;
    if (totalSaved < goalTarget!) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final already = prefs.getBool('goalNotified') ?? false;
      if (already) return;
      await NotificationHelper.showSimple(
        1001,
        'Hedefe Ulaştın! 🎉',
        'Tasarruf hedefinize ulaştınız. Harikasınız!',
      );
      await prefs.setBool('goalNotified', true);
    } catch (_) {}
  }

  Future<void> _persistUnitMeasure() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('unitLengthCm', _unitLengthCm);
      await prefs.setString('unitName', _unitName);
      if (_packSize != null && _packSize! > 0) {
        await prefs.setInt('packSize', _packSize!);
      } else {
        await prefs.remove('packSize');
      }
    } catch (_) {}
  }

  // Şu anki iyileşme/çekilme evresi (genel bilgilendirme amaçlı)
  ({String title, String detail})? _currentStageInfo() {
    if (quitTime == null) return null;
    final diff = DateTime.now().difference(quitTime!);
    final mins = diff.inMinutes;
    final hours = diff.inHours;
    final days = diff.inDays;

    String title;
    String detail;

    if (mins < 20) {
      title = 'İlk adımlar: Vücudun dengeleniyor';
      detail =
          'Kalp atışın ve tansiyonun yavaş yavaş normale iniyor. Derin ve yavaş nefesler iyi gelir.';
    } else if (hours < 12) {
      title = 'İlk saatler: Dolaşım dengesi';
      detail =
          'Tansiyon ve nabız normale yaklaşır. Ellerde/ayaklarda ısınma hissi olabilir.';
    } else if (hours < 24) {
      title = '12–24 saat: Kan temizleniyor';
      detail =
          'Kandaki karbonmonoksit normale döner; oksijenlenme artar, organların daha iyi çalışır.';
    } else if (hours < 48) {
      title = '24–48 saat: Duyular geri geliyor';
      detail =
          'Nikotin hızla azalır; tat ve koku duyusu belirginleşmeye başlar. Krizler dalga dalga gelebilir.';
    } else if (hours < 72) {
      title = '48–72 saat: Zor kısım zirve';
      detail =
          'Yoksunluk belirtileri (huzursuzluk, odaklanma zorluğu) en yoğun olabilir; her dalga 5–10 dk sürer.';
    } else if (days < 7) {
      title = '1. hafta: Akciğerler rahatlıyor';
      detail =
          'Nefes almak kolaylaşır; öksürük geçici artabilir. Krizler seyrekleşir ve kısalır.';
    } else if (days < 14) {
      title = '2. hafta: Dolaşım belirgin iyileşiyor';
      detail =
          'Enerji ve yürüyüş performansı artar. Uyku ve iştah dengesi oturmaya başlar.';
    } else if (days < 90) {
      title = '2–12 hafta: Kondisyon artışı';
      detail =
          'Akciğer fonksiyonu ve dolaşım iyileşir; merdivenler kolaylaşır, egzersiz toleransı artar.';
    } else if (days < 270) {
      title = '1–9 ay: Akciğer temizliği';
      detail =
          'Akciğerlerdeki tüycüklü yapı (silia) toparlanır; öksürük ve nefes darlığı azalır.';
    } else if (days < 365) {
      title = '1 yıla doğru: Büyük risk azalması';
      detail =
          'Koroner kalp hastalığı riski hatırı sayılır azalır; günlük yaşam kalitesi artar.';
    } else if (days < 5 * 365) {
      title = '1–5 yıl: Koruma güçleniyor';
      detail = 'Felç (inme) riski düşmeye devam eder; damar sağlığı iyileşir.';
    } else if (days < 10 * 365) {
      title = '5–10 yıl: Kanser riski düşüyor';
      detail =
          'Ağız, boğaz ve akciğer kanseri riskleri içenlere göre anlamlı ölçüde azalır.';
    } else if (days < 15 * 365) {
      title = '10–15 yıl: Uzun vadeli kazanım';
      detail =
          'Akciğer kanseri kaynaklı ölüm riski içenlerin yaklaşık yarısına iner.';
    } else {
      title = '15+ yıl: Neredeyse hiç içmemiş gibi';
      detail = 'Kalp-damar hastalıkları riski hiç içmemiş birine yaklaşır.';
    }

    // Erken dönem düşünce tuzağı hatırlatması
    if (days < 7) {
      detail +=
          ' • Şu an “bir tane içsem bozmaz” düşüncesi gelebilir; bu düşünce dalgası geçicidir. Nefese dön, 5–10 dk içinde azalır.';
    }

    return (title: title, detail: detail);
  }

  // Kriz Modu sayfasını aç
  void _openCrisisMode() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CrisisModePage()));
  }

  // Yüksek risk saatlerinde nazik uyarılar (günlük 3 zaman)
  Future<void> _toggleRiskReminders() async {
    setState(() => _riskRemindersOn = !_riskRemindersOn);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('riskRemindersOn', _riskRemindersOn);
    if (_riskRemindersOn) {
      await NotificationHelper.scheduleDailyRisk(
        2001,
        9,
        0,
        'Şefkatli Hatırlatma',
        'Kısa bir nefes molası al. Kriz dalgası geçer, nefesine dön.',
      );
      await NotificationHelper.scheduleDailyRisk(
        2002,
        15,
        0,
        'Kendine İyi Bak',
        'Su iç, mini yürüyüş yap. Bir düşünce, bir karar değildir.',
      );
      await NotificationHelper.scheduleDailyRisk(
        2003,
        21,
        0,
        'Akşam Sakinliği',
        'Geceleri istek yükselebilir. 2 dk nefes egzersizi dene.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Günlük hatırlatmalar ayarlandı.')),
        );
      }
    } else {
      await NotificationHelper.cancelAllRisk();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Günlük hatırlatmalar kapatıldı.')),
        );
      }
    }
  }

  // Grafik fonksiyonları kaldırıldı

  @override
  Widget build(BuildContext context) {
    // Responsive metrics for this screen
    final media = MediaQuery.of(context);
    final screenW = media.size.width;
    final bigNumberFont = (screenW * 0.10).clamp(28.0, 40.0).toDouble();
    final sectionTitleFont = (screenW * 0.055).clamp(16.0, 22.0).toDouble();
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      extendBodyBehindAppBar: false,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Bağımlılık Tasarruf Takip',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        leading: const Icon(Icons.savings, color: Colors.white),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6D5DF6), Color(0xFF46C2CB)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 16.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                // Aynı boyutta, alt alta cam efektli butonlar
                GlassButton(
                  icon: Icons.edit,
                  label: 'Bağımlılık Bilgisi Gir',
                  onPressed: _showInputDialog,
                ),
                const SizedBox(height: 12),
                GlassButton(
                  icon: Icons.flag,
                  label: 'Hedef Miktar Ekle',
                  onPressed: _showGoalDialog,
                ),
                const SizedBox(height: 12),
                GlassButton(
                  icon:
                      _riskRemindersOn
                          ? Icons.notifications_active
                          : Icons.notifications,
                  label:
                      _riskRemindersOn
                          ? 'Yüksek Risk Uyarıları: Açık'
                          : 'Yüksek Risk Uyarıları: Kapalı',
                  onPressed: _toggleRiskReminders,
                ),
                const SizedBox(height: 12),
                GlassButton(
                  icon: Icons.bolt,
                  label: 'Beni Motive Et (Kriz Anındayım)',
                  onPressed: _showMotivationDialog,
                ),
                const SizedBox(height: 12),
                GlassButton(
                  icon: Icons.self_improvement,
                  label: 'Kriz Modu – Nefes Egzersizi',
                  onPressed: _openCrisisMode,
                ),
                const SizedBox(height: 30),
                if (dailyCost != null &&
                    dailyAmount != null &&
                    quitTime != null) ...[
                  FrostedCard(
                    borderRadius: 24,
                    child: Padding(
                      padding: const EdgeInsets.all(28.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.celebration,
                            color: Color(0xFF6D5DF6),
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Tasarruf Edilen Tutar',
                            style: GoogleFonts.poppins(
                              fontSize: sectionTitleFont,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 10),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 350),
                            transitionBuilder:
                                (child, anim) =>
                                    FadeTransition(opacity: anim, child: child),
                            child: SizedBox(
                              width: double.infinity,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _money(totalSaved, decimals: 2),
                                  key: ValueKey((totalSaved * 100).round()),
                                  style: GoogleFonts.poppins(
                                    fontSize: bigNumberFont,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF46C2CB),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Builder(
                            builder: (context) {
                              final stage = _currentStageInfo();
                              if (stage == null) return const SizedBox.shrink();
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF2F6FF),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.health_and_safety,
                                      color: Color(0xFF6D5DF6),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            stage.title,
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            stage.detail,
                                            style: GoogleFonts.poppins(
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          if (goalTarget != null) ...[
                            const SizedBox(height: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Hedef: ${_money(goalTarget!, decimals: 0)}',
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${(totalSaved / goalTarget!).clamp(0, 1) * 100 ~/ 1}%',
                                      style: GoogleFonts.poppins(
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: (totalSaved / goalTarget!).clamp(
                                      0,
                                      1,
                                    ),
                                    minHeight: 10,
                                    backgroundColor: Colors.grey.shade200,
                                    color: const Color(0xFF6D5DF6),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Builder(
                                  builder: (context) {
                                    final rem = (goalTarget! - totalSaved);
                                    if (rem <= 0) {
                                      return Text(
                                        'Tebrikler! Hedefe ulaştın 🎉',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.poppins(
                                          color: Colors.black,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      );
                                    }
                                    final days = _daysToGoal;
                                    String eta = '—';
                                    if (days == double.infinity) {
                                      eta = '—';
                                    } else if (days != null) {
                                      final wholeDays = days.ceil();
                                      eta = '$wholeDays gün';
                                    }
                                    return Text(
                                      'Kalan: ${_money(rem, decimals: 0)} • Tahmini: $eta',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.poppins(
                                        color: Colors.black54,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 18),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(
                                avatar: const Icon(
                                  Icons.calendar_today,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                label: Text(
                                  'Başlangıç: '
                                  '${_formatDate(quitTime!.toLocal())} '
                                  '${_formatTime(TimeOfDay.fromDateTime(quitTime!.toLocal()))}',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                backgroundColor: Colors.grey.shade600,
                              ),
                              Chip(
                                avatar: const Icon(
                                  Icons.local_fire_department,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                label: Text(
                                  'Günlük: $dailyAmount',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                  ),
                                ),
                                backgroundColor: Colors.orange.shade400,
                              ),
                              Chip(
                                avatar: const Icon(
                                  Icons.attach_money,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                label: Text(
                                  'Birim Ücret: ${_money(dailyCost!, decimals: 2)}',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                  ),
                                ),
                                backgroundColor: Colors.green,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Metinsel istatistikler (grafik yok)
                  FrostedCard(
                    borderRadius: 20,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'İlerleme ve Bilgiler',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(
                                Icons.trending_up,
                                size: 18,
                                color: Color(0xFF6D5DF6),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Günlük tasarruf: ${_money(_dailyRate, decimals: 2)}/gün',
                                style: GoogleFonts.poppins(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const SizedBox(width: 26),
                              Text(
                                'Haftalık ~ ${_money(7 * _dailyRate, decimals: 0)} • Aylık ~ ${_money(30 * _dailyRate, decimals: 0)}',
                                style: GoogleFonts.poppins(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.block,
                                size: 18,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Toplam bırakılan miktar: ${_totalAvoidedUnits.floor()} birim',
                                style: GoogleFonts.poppins(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.favorite,
                                size: 18,
                                color: Colors.redAccent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Tahmini yaşam süresi kazanımı: $_lifeGainedHumanReadable',
                                  style: GoogleFonts.poppins(),
                                ),
                              ),
                            ],
                          ),
                          if (goalTarget != null) ...[
                            const Divider(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Hedef Detayları',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                TextButton(
                                  onPressed: _clearGoal,
                                  child: Text(
                                    'Hedefi Temizle',
                                    style: GoogleFonts.poppins(),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'Kalan: ${_money(goalTarget! - totalSaved <= 0 ? 0 : goalTarget! - totalSaved, decimals: 0)}',
                              style: GoogleFonts.poppins(),
                            ),
                            const SizedBox(height: 4),
                            Builder(
                              builder: (context) {
                                final d = _daysToGoal;
                                if (d == null || d == double.infinity) {
                                  return Text(
                                    'Tahmini süre: —',
                                    style: GoogleFonts.poppins(),
                                  );
                                }
                                if (d <= 0) {
                                  return Text(
                                    'Hedefe ulaşıldı!',
                                    style: GoogleFonts.poppins(),
                                  );
                                }
                                return Text(
                                  'Tahmini süre: ${d.ceil()} gün',
                                  style: GoogleFonts.poppins(),
                                );
                              },
                            ),
                            if (_etaDateText != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Hedef tarihi (tahmini): $_etaDateText',
                                style: GoogleFonts.poppins(),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Yeni: Birim uzunluğu karşılaştırmaları + alternatif kıyaslar
                  FrostedCard(
                    borderRadius: 20,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Eğlenceli Karşılaştırmalar',
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 140,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: TextButton.icon(
                                    onPressed: _showUnitMeasureDialog,
                                    icon: const Icon(Icons.tune, size: 18),
                                    label: Text(
                                      '${_unitLengthCm.toStringAsFixed(1)} cm',
                                      style: GoogleFonts.poppins(),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Builder(
                            builder: (context) {
                              final units = _totalUnitsExact;
                              final packs = _packsCount;
                              final meters = _totalMeters;
                              String metersText;
                              if (meters < 1 && meters >= 0) {
                                metersText =
                                    '${(meters * 100).toStringAsFixed(1)} cm';
                              } else {
                                metersText = '${meters.toStringAsFixed(2)} m';
                              }
                              final humanHeight = 1.70; // m
                              final floorHeight = 3.0; // m
                              final humans =
                                  humanHeight > 0
                                      ? (meters / humanHeight)
                                      : 0.0;
                              final floors =
                                  floorHeight > 0
                                      ? (meters / floorHeight)
                                      : 0.0;
                              final fiveStoryBuildings = floors / 5.0;
                              // Alternatif kıyaslar
                              const double bogazBridgeLengthM =
                                  1560.0; // yaklaşık total uzunluk
                              const double footballFieldLenM =
                                  105.0; // FIFA standart uzunluk
                              final bogazBridges =
                                  bogazBridgeLengthM > 0
                                      ? meters / bogazBridgeLengthM
                                      : 0.0;
                              final footballFields =
                                  footballFieldLenM > 0
                                      ? meters / footballFieldLenM
                                      : 0.0;

                              // Metinleri dinamik oluştur
                              final String unitsLine =
                                  units >= 1
                                      ? 'Toplam: ${units.floor()} $_unitName'
                                      : 'Toplam: ~${units.toStringAsFixed(2)} $_unitName';
                              String? packsLine;
                              if (packs != null) {
                                if (packs > 0 && packs < 0.1) {
                                  packsLine = '≈ <0.1 paket';
                                } else {
                                  packsLine =
                                      '≈ ${packs.toStringAsFixed(1)} paket';
                                }
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.smoking_rooms,
                                        size: 18,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          unitsLine,
                                          style: GoogleFonts.poppins(),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (packsLine != null) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const SizedBox(width: 26),
                                        Expanded(
                                          child: Text(
                                            packsLine,
                                            style: GoogleFonts.poppins(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.straighten,
                                        size: 18,
                                        color: Color(0xFF6D5DF6),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Uç uca: $metersText',
                                          style: GoogleFonts.poppins(),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.person,
                                        size: 18,
                                        color: Colors.green,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Ortalama insan boyunun ~${humans.toStringAsFixed(1)} katı',
                                          style: GoogleFonts.poppins(
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.apartment,
                                        size: 18,
                                        color: Colors.orange,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '~${floors.toStringAsFixed(1)} kat yüksekliğinde (≈ ${fiveStoryBuildings.toStringAsFixed(2)} adet 5 katlı bina)',
                                          style: GoogleFonts.poppins(),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.architecture,
                                        size: 18,
                                        color: Colors.blueGrey,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '≈ ${bogazBridges.toStringAsFixed(3)} Boğaz Köprüsü uzunluğu',
                                          style: GoogleFonts.poppins(),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.sports_soccer,
                                        size: 18,
                                        color: Colors.black87,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '≈ ${footballFields.toStringAsFixed(2)} futbol sahası uzunluğu',
                                          style: GoogleFonts.poppins(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  FrostedCard(
                    borderRadius: 20,
                    child: const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text(
                        'Lütfen bağımlılık bilgilerinizi girin.',
                        style: TextStyle(fontSize: 18, color: Colors.black54),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Modern cam efekti: frosted glass kart
class FrostedCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  const FrostedCard({super.key, required this.child, this.borderRadius = 16});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class GlassButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const GlassButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: const SizedBox.shrink(),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                splashColor: Colors.white.withValues(alpha: 0.1),
                highlightColor: Colors.white.withValues(alpha: 0.06),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(icon, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.white70),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 2 dakikalık Kriz Modu: Nefes egzersizi + geri sayım
class CrisisModePage extends StatefulWidget {
  const CrisisModePage({super.key});

  @override
  State<CrisisModePage> createState() => _CrisisModePageState();
}

class _CrisisModePageState extends State<CrisisModePage>
    with SingleTickerProviderStateMixin {
  static const int totalSeconds = 120; // 2 dakika
  static const int inhaleSeconds = 4;
  static const int holdSeconds = 2;
  static const int exhaleSeconds = 6;
  static const int cycleSeconds =
      inhaleSeconds + holdSeconds + exhaleSeconds; // 12s

  late final AnimationController _breathController;
  Timer? _countdown;
  int _remaining = totalSeconds;
  // Kriz anı mesajları (TR) – 3 saniyede bir rastgele gösterilecek
  static const List<String> _crisisMessages = [
    'Şu anki istek dalga gibi gelir ve geçer. Nefesine odaklan.',
    '3 dakika kuralı: 3 dakika oyala, istek azalır.',
    'Bir sigara şu an seni geriye götürür. Dayanıyorsun.',
    'Su iç, kısa bir yürüyüş yap veya esne; bedenini meşgul et.',
    'Bu zorluk geçici, kazancın kalıcı. Sabret.',
    'Bir tane asla bir tane değildir. Zinciri kırma.',
    'Kendinle gurur duy, bu anı da atlatırsın.',
    'Düşünce geçer; gerçeğin: Sigarasız da rahatsın.',
    'Cebindeki para ve özgürlüğün artıyor, devam et.',
    'Kriz 5–10 dk sürer, sen daha güçlüsün.',
  ];
  final Random _rng = Random();
  String _currentMsg = _crisisMessages.first;
  Timer? _msgTicker;

  @override
  void initState() {
    super.initState();
    _breathController =
        AnimationController(
            vsync: this,
            duration: const Duration(seconds: cycleSeconds),
          )
          ..addListener(() {
            if (!mounted) return;
            setState(() {});
          })
          ..repeat();

    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _remaining--;
      });
      if (_remaining <= 0) {
        t.cancel();
        _breathController.stop();
        if (!mounted) return;
        showDialog(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Tebrikler!'),
                content: const Text('Kriz modu tamamlandı.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Tamam'),
                  ),
                ],
              ),
        ).then((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    });

    // 3 saniyede bir rastgele kriz mesajı göster
    _msgTicker = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() {
        _currentMsg = _pickNewMessage(_currentMsg);
      });
    });
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _msgTicker?.cancel();
    _breathController.dispose();
    super.dispose();
  }

  String _formatMMSS(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // Mevcut fazı ve daire ölçeğini hesapla
  ({String phase, double scale}) _phaseAndScale() {
    final v = _breathController.value; // 0..1
    final current = (v * cycleSeconds);
    if (current < inhaleSeconds) {
      final p = current / inhaleSeconds; // 0..1
      // 0.85 -> 1.15
      return (phase: 'Nefes al', scale: 0.85 + 0.30 * p);
    } else if (current < inhaleSeconds + holdSeconds) {
      // sabit tepe
      return (phase: 'Tut', scale: 1.15);
    } else {
      final ex = current - inhaleSeconds - holdSeconds; // 0..exhale
      final p = (ex / exhaleSeconds).clamp(0.0, 1.0);
      // 1.15 -> 0.85
      return (phase: 'Ver', scale: 1.15 - 0.30 * p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = _phaseAndScale();
    final media = MediaQuery.of(context);
    final sw = media.size.width;
    final circleSize = (sw * 0.55).clamp(160.0, 260.0).toDouble();
    final timerFont = (sw * 0.11).clamp(28.0, 44.0).toDouble();
    final phaseFont = (sw * 0.06).clamp(18.0, 24.0).toDouble();

    return Scaffold(
      backgroundColor: const Color(0xFF0E0F2F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Kriz Modu'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Bitir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1F1C2C), Color(0xFF928DAB)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _formatMMSS(_remaining),
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: timerFont,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    phase.phase,
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontSize: phaseFont,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 32),
                  AnimatedBuilder(
                    animation: _breathController,
                    builder:
                        (context, child) =>
                            Transform.scale(scale: phase.scale, child: child),
                    child: Container(
                      width: circleSize,
                      height: circleSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          colors: [Color(0xFF46C2CB), Color(0xFF6D5DF6)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '4 sn al • 2 sn tut • 6 sn ver',
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 3 sn'de bir değişen kriz anı mesajı
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      _currentMsg,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Aynı mesajı arka arkaya verme
  String _pickNewMessage(String? exclude) {
    if (_crisisMessages.length <= 1) return _crisisMessages.first;
    String next = _crisisMessages[_rng.nextInt(_crisisMessages.length)];
    if (exclude != null && _crisisMessages.length > 1) {
      int safeties = 0;
      while (next == exclude && safeties < 5) {
        next = _crisisMessages[_rng.nextInt(_crisisMessages.length)];
        safeties++;
      }
    }
    return next;
  }
}
