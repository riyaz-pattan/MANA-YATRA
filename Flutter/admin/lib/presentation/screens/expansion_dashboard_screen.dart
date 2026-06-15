// lib/presentation/screens/expansion_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ExpansionDashboardScreen extends StatefulWidget {
  const ExpansionDashboardScreen({super.key});
  @override
  State<ExpansionDashboardScreen> createState() => _ExpansionDashboardScreenState();
}

class _ExpansionDashboardScreenState extends State<ExpansionDashboardScreen> {
  final _database = FirebaseDatabase.instance.ref('waitlist');
  List<Map<String, dynamic>> _waitlist = [];
  bool _isLoading = true;
  int _riderCount = 0;
  int _driverCount = 0;
  Set<Marker> _markers = {};
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _loadWaitlist();
  }

  Future<void> _loadWaitlist() async {
    _database.onValue.listen((event) {
      if (event.snapshot.value == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      
      final Map<dynamic, dynamic> data = event.snapshot.value as Map;
      List<Map<String, dynamic>> tempList = [];
      int rCount = 0;
      int dCount = 0;
      Set<Marker> tMarkers = {};
      
      data.forEach((key, value) {
        final item = Map<String, dynamic>.from(value as Map);
        tempList.add(item);
        
        final type = item['type'] as String? ?? 'rider';
        if (type == 'rider') rCount++;
        else dCount++;
        
        final lat = (item['lat'] as num?)?.toDouble() ?? 0.0;
        final lng = (item['lng'] as num?)?.toDouble() ?? 0.0;
        
        tMarkers.add(Marker(
          markerId: MarkerId(key.toString()),
          position: LatLng(lat, lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            type == 'rider' ? BitmapDescriptor.hueRed : BitmapDescriptor.hueBlue,
          ),
          infoWindow: InfoWindow(title: '${type.toUpperCase()} Interest', snippet: item['phone'] ?? ''),
        ));
      });
      
      if (mounted) {
        setState(() {
          _waitlist = tempList;
          _riderCount = rCount;
          _driverCount = dCount;
          _markers = tMarkers;
          _isLoading = false;
        });
        
        if (_waitlist.isNotEmpty && _mapController != null) {
          _mapController!.animateCamera(CameraUpdate.newLatLngZoom(
            LatLng(_waitlist.first['lat'], _waitlist.first['lng']), 10,
          ));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Side - Map
          Expanded(
            flex: 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _waitlist.isEmpty
                  ? Center(child: Text('No waitlist data yet.', style: GoogleFonts.inter()))
                  : GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(_waitlist.first['lat'], _waitlist.first['lng']),
                        zoom: 10,
                      ),
                      markers: _markers,
                      onMapCreated: (controller) => _mapController = controller,
                    ),
            ),
          ),
          const SizedBox(width: 16),
          // Right Side - Stats & Table
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Expansion Demand', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(child: _buildStatCard('Riders', _riderCount, Colors.red)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildStatCard('Drivers', _driverCount, Colors.blue)),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Recent Waitlist Entries', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.separated(
                      itemCount: _waitlist.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _waitlist[index];
                        return ListTile(
                          leading: Icon(
                            item['type'] == 'rider' ? Icons.person : Icons.drive_eta,
                            color: item['type'] == 'rider' ? Colors.red : Colors.blue,
                          ),
                          title: Text(item['phone'] ?? 'Unknown Phone', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                          subtitle: Text('Lat: ${item['lat'].toStringAsFixed(4)}, Lng: ${item['lng'].toStringAsFixed(4)}', style: GoogleFonts.inter(fontSize: 12)),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, int count, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(title, style: GoogleFonts.inter(fontSize: 14, color: color, fontWeight: FontWeight.w600)),
          Text(count.toString(), style: GoogleFonts.inter(fontSize: 24, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
