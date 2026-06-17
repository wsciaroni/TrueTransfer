import 'package:flutter/material.dart';
import 'ui/home_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrueTransfer',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.blueAccent,
        colorScheme: const ColorScheme.dark(
          primary: Colors.blueAccent,
          secondary: Colors.cyan,
          surface: Color(0xFF121212),
          error: Colors.redAccent,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey[950],
          foregroundColor: Colors.white,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.grey[950],
          indicatorColor: Colors.blueAccent.withOpacity(0.15),
        ),
      ),
      home: const HomePage(),
    );
  }
}
