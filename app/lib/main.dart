import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'runpod.dart';
import 'screens/home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Sistem çubukları içeriğin üstüne binmesin: edge-to-edge kapalı, SafeArea ile çalışıyoruz
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Api.I.load();
  await RunPod.I.load();
  runApp(const FaceSwapApp());
}

class FaceSwapApp extends StatelessWidget {
  const FaceSwapApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF7C4DFF), brightness: Brightness.dark);
    return MaterialApp(
      title: 'FaceSwap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF121218),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF121218), elevation: 0, centerTitle: false),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ),
      ),
      builder: (context, child) {
        // Yazı ölçeğini sınırla: dev yazı ayarında düzen bozulmasın
        final mq = MediaQuery.of(context);
        return MediaQuery(data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.2)), child: child!);
      },
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [cs.primary, cs.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.face_retouching_natural, size: 56, color: Colors.white),
            ),
            const SizedBox(height: 20),
            const Text('FaceSwap', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: 1)),
            const SizedBox(height: 6),
            Text('Videoda yüz değiştir', style: TextStyle(fontSize: 15, color: cs.onSurface.withOpacity(0.7))),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('created by Ozgur Gokce', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5))),
            ),
          ],
        ),
      ),
    );
  }
}
