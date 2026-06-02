import 'package:flutter/material.dart';

import 'screens/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AutoRememberApp());
}

class AutoRememberApp extends StatelessWidget {
  const AutoRememberApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff287d6f);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '债务追踪',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xfff7f8f5),
        appBarTheme: const AppBarTheme(centerTitle: false),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      home: const HomePage(),
    );
  }
}