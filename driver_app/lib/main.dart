import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'login_screen.dart';
import 'map_screen.dart';

void main() {
  runApp(const RideApp());
}

class RideApp extends StatelessWidget {
  const RideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Equinox',
      theme: ThemeData(
        useMaterial3: true, 
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0B),
        textTheme: GoogleFonts.dmSansTextTheme().apply(
          bodyColor: const Color(0xFFE8E2D9),
          displayColor: const Color(0xFFE8E2D9),
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFC9A96E),
          surface: Color(0xFF0F0F0D),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Color(0xFFC4BBA8), size: 22),
          titleTextStyle: GoogleFonts.spaceMono(
            color: const Color(0xFFE8E2D9),
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone');
    final name = prefs.getString('user_name') ?? "Driver";

    if (!mounted) return;

    // TESTING MODE: Disable auto-login bypass
    /*
    if (phone != null && phone.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => MapScreen(driverName: name, driverPhone: phone)),
      );
    } else {
    */
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    // }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: const Color(0xFF0A0A0B),
      body: const Center(
        child: CircularProgressIndicator(color: Color(0xFFC9A96E)),
      ),
    );
  }
}
