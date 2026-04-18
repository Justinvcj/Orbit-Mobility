import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://svrtdphfclhhsdwekyiy.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN2cnRkcGhmY2xoaHNkd2VreWl5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQxMTU5NDIsImV4cCI6MjA3OTY5MTk0Mn0.Pn3b02gOYxhYGhZI0-mIKrbUwOxumM2an67ytPmSQp0',
  );
  runApp(const EquinoxAdminApp());
}

class EquinoxAdminApp extends StatelessWidget {
  const EquinoxAdminApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Equinox God Mode',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0B),
        cardColor: const Color(0xFF161613),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _supabase = Supabase.instance.client;

  double _totalRevenue = 0;
  int _activeRidesCount = 0;
  int _suspendedDriversCount = 0;

  List<dynamic> _recentRides = [];
  List<dynamic> _driverReports = [];

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  void _initStreams() {
    // 1. Rides Stream
    _supabase.from('rides').stream(primaryKey: ['id']).order('created_at').listen((data) {
      if (!mounted) return;
      setState(() {
        _recentRides = data.reversed.take(50).toList();
        _activeRidesCount = data.where((r) => ['REQUESTED', 'ACCEPTED', 'IN_PROGRESS'].contains(r['status'])).length;
      });
    });

    // 2. Admin Ledger Stream
    _supabase.from('admin_ledger').stream(primaryKey: ['id']).listen((data) {
      if (!mounted) return;
      double total = 0;
      for (var entry in data) {
         total += (entry['amount'] ?? 0).toDouble();
      }
      setState(() { _totalRevenue = total; });
    });

    // 3. Reports Stream
    _supabase.from('driver_reports').stream(primaryKey: ['id']).order('timestamp').listen((data) {
      if (!mounted) return;
      setState(() {
        _driverReports = data.reversed.take(50).toList();
      });
    });
    
    // Total Suspended Drivers logic 
    _supabase.from('users').stream(primaryKey: ['id']).eq('role', 'driver').listen((data) {
       if (!mounted) return;
       setState(() {
         _suspendedDriversCount = data.where((u) => u['is_banned'] == true || u['is_suspended'] == true).length;
       });
    });
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF161613),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1E1C17)),
          boxShadow: const [BoxShadow(color: Colors.black26, offset: Offset(0, 4), blurRadius: 10)]
        ),
        child: Row(
          children: [
            CircleAvatar(radius: 30, backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color, size: 30)),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.dmSans(color: const Color(0xFF6B6556), fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(value, style: GoogleFonts.cormorantGaramond(color: const Color(0xFFE8E2D9), fontSize: 36, fontWeight: FontWeight.bold)),
                ]
              )
            )
          ]
        )
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("EQUINOX // GOD MODE", style: GoogleFonts.dmSans(letterSpacing: 2, fontWeight: FontWeight.w900, color: const Color(0xFFC9A96E))),
        backgroundColor: const Color(0xFF0F0F0D),
        elevation: 0,
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(color: const Color(0xFF1E1C17), height: 1)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // TOP METRICS
            Row(
              children: [
                _buildMetricCard("Live Revenue Vault", "₹${_totalRevenue.toStringAsFixed(0)}", Icons.account_balance, const Color(0xFFC9A96E)),
                _buildMetricCard("Active Live Rides", "$_activeRidesCount", Icons.electric_car, Colors.blueAccent),
                _buildMetricCard("Suspended Drivers", "$_suspendedDriversCount", Icons.gavel, Colors.redAccent),
              ],
            ),
            const SizedBox(height: 24),
            // LOWER GRID
            Expanded(
              child: Row(
                children: [
                  // LEFT PILLAR (RIDES)
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(color: const Color(0xFF161613), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF1E1C17))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text("Live Operations Pipeline", style: GoogleFonts.dmSans(color: const Color(0xFFC9A96E), fontWeight: FontWeight.bold, fontSize: 18)),
                          ),
                          const Divider(color: Color(0xFF1E1C17), height: 1),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _recentRides.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (ctx, i) {
                                final ride = _recentRides[i];
                                Color statusColor = Colors.grey;
                                if (ride['status'] == 'IN_PROGRESS') statusColor = Colors.blue;
                                if (ride['status'] == 'COMPLETED') statusColor = Colors.green;
                                if (ride['status'] == 'CANCELLED') statusColor = Colors.red;
                                
                                return ListTile(
                                  tileColor: const Color(0xFF0F0F0D),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  title: Text("${ride['pickup']} → ${ride['dropoff']}", style: const TextStyle(color: Colors.white, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text("Rider: ${ride['rider_phone']} • Driver: ${ride['driver_phone']}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                  trailing: Chip(
                                    label: Text(ride['status'], style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                                    backgroundColor: statusColor.withOpacity(0.1),
                                    side: BorderSide.none,
                                  ),
                                );
                              }
                            )
                          )
                        ]
                      )
                    )
                  ),
                  const SizedBox(width: 24),
                  // RIGHT PILLAR (MODERATION QUEUE)
                  Expanded(
                    flex: 1,
                    child: Container(
                      decoration: BoxDecoration(color: const Color(0xFF161613), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF1E1C17))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text("Trust & Safety Queue", style: GoogleFonts.dmSans(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 18)),
                          ),
                          const Divider(color: Color(0xFF1E1C17), height: 1),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _driverReports.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (ctx, i) {
                                final report = _driverReports[i];
                                return ListTile(
                                  tileColor: const Color(0xFF0F0F0D),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                                  title: Text("Driver: ${report['driver_phone']}", style: const TextStyle(color: Colors.white, fontSize: 13)),
                                  subtitle: Text("Reason: ${report['reason']}", style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                                );
                              }
                            )
                          )
                        ]
                      )
                    )
                  )
                ]
              )
            )
          ]
        )
      )
    );
  }
}
