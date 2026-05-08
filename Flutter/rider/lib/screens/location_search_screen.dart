// lib/screens/location_search_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/ride_provider.dart';
import '../services/google_maps_service.dart';
import 'map_picker_screen.dart';

/// Full-screen location search experience.
/// Returns `true` via Navigator.pop when both pickup and drop are set.
class LocationSearchScreen extends StatefulWidget {
  /// Current device position (used for distance calculations and map picker).
  final LatLng currentPosition;

  /// Saved Home location from Firestore (nullable).
  final Map<String, dynamic>? savedHome;

  /// Saved Work location from Firestore (nullable).
  final Map<String, dynamic>? savedWork;

  /// Whether to auto-focus a specific field.
  /// true = drop, false = pickup, null = default logic.
  final bool? focusDrop;

  const LocationSearchScreen({
    super.key,
    required this.currentPosition,
    this.savedHome,
    this.savedWork,
    this.focusDrop,
  });

  @override
  State<LocationSearchScreen> createState() => _LocationSearchScreenState();
}

enum _ActiveField { pickup, drop }

class _LocationSearchScreenState extends State<LocationSearchScreen> {
  final _pickupController = TextEditingController();
  final _dropController = TextEditingController();
  final _pickupFocus = FocusNode();
  final _dropFocus = FocusNode();

  _ActiveField _activeField = _ActiveField.drop;
  List<PlacePrediction> _searchResults = [];
  bool _searching = false;
  bool _fetchingDetails = false;
  Timer? _debounce;

  // Track if pickup is "Your Current Location" (auto-set)
  bool _pickupIsCurrentLocation = true;

  @override
  void initState() {
    super.initState();
    
    // Populate existing values if any
    final provider = context.read<RideProvider>();
    if (provider.pickup != null) {
      final distance = Geolocator.distanceBetween(
        widget.currentPosition.latitude,
        widget.currentPosition.longitude,
        provider.pickup!.lat,
        provider.pickup!.lng,
      );
      // If within 100m, consider it "Your Location"
      if (distance < 100) {
        _pickupController.text = 'Your Location';
        _pickupIsCurrentLocation = true;
      } else {
        _pickupController.text = provider.pickup!.displayName;
        _pickupIsCurrentLocation = false;
      }
    } else {
      _pickupController.text = 'Your Location';
      _pickupIsCurrentLocation = true;
    }

    if (provider.drop != null) {
      _dropController.text = provider.drop!.displayName;
    }

    // Listen to focus changes to restore "Your Location" if cleared
    _pickupFocus.addListener(() {
      if (_pickupFocus.hasFocus) GoogleMapsService.startNewSearchSession();
      if (mounted) setState(() {});
      if (!_pickupFocus.hasFocus && 
          _pickupController.text.isEmpty && 
          _pickupIsCurrentLocation) {
        _pickupController.text = 'Your Location';
      }
    });
    _dropFocus.addListener(() { 
      if (_dropFocus.hasFocus) GoogleMapsService.startNewSearchSession();
      if (mounted) setState(() {}); 
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.focusDrop == true) {
        setState(() => _activeField = _ActiveField.drop);
        _dropFocus.requestFocus();
      } else if (widget.focusDrop == false) {
        setState(() => _activeField = _ActiveField.pickup);
        _pickupFocus.requestFocus();
      } else {
        // Default behavior (null)
        if (_dropController.text.isEmpty) {
          setState(() => _activeField = _ActiveField.drop);
          _dropFocus.requestFocus();
        } else {
          setState(() => _activeField = _ActiveField.pickup);
          _pickupFocus.requestFocus();
        }
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pickupController.dispose();
    _dropController.dispose();
    _pickupFocus.dispose();
    _dropFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    
    // If user starts typing in pickup, it's no longer "Current Location"
    if (_activeField == _ActiveField.pickup && _pickupIsCurrentLocation && query.isNotEmpty) {
      setState(() => _pickupIsCurrentLocation = false);
    }

    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _searching = true);
      final results = await GoogleMapsService.getPlacePredictions(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _searching = false;
        });
      }
    });
  }

  void _selectLocation(LocationResult location) {
    final provider = context.read<RideProvider>();

    if (_activeField == _ActiveField.pickup) {
      provider.setPickup(location);
      _pickupController.text = location.displayName;
      _pickupIsCurrentLocation = false;
      setState(() {
        _searchResults = [];
      });
      // Move focus to drop
      _dropFocus.requestFocus();
      _activeField = _ActiveField.drop;
    } else {
      provider.setDrop(location);
      _dropController.text = location.displayName;
      setState(() {
        _searchResults = [];
      });
      // Both locations set — pop back with result
      if (provider.pickup != null) {
        Navigator.pop(context, true);
      }
    }
  }

  void _selectSavedPlace(Map<String, dynamic> place, String label) {
    final loc = LocationResult(
      placeId: '',
      displayName: place['display_name'] ?? '',
      shortName: place['short_name'] ?? label,
      lat: (place['lat'] as num).toDouble(),
      lng: (place['lng'] as num).toDouble(),
    );
    _selectLocation(loc);
  }

  Future<void> _openMapPicker() async {
    final title = _activeField == _ActiveField.pickup
        ? 'Select Pickup'
        : 'Select Drop-off';

    final result = await Navigator.push<LocationResult>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialPosition: widget.currentPosition,
          title: title,
        ),
      ),
    );

    if (result != null && mounted) {
      _selectLocation(result);
    }
  }

  /// Calculate straight-line distance between current position and a search result.
  String _formatDistance(LocationResult result) {
    final distMeters = Geolocator.distanceBetween(
      widget.currentPosition.latitude,
      widget.currentPosition.longitude,
      result.lat,
      result.lng,
    );
    if (distMeters < 1000) {
      return '${distMeters.round()} m';
    } else {
      return '${(distMeters / 1000).toStringAsFixed(1)} km';
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Column(
        children: [
          // ── Header ──
          Container(
            padding: EdgeInsets.fromLTRB(4, topPadding + 8, 16, 12),
            decoration: const BoxDecoration(
              color: AppTheme.bg,
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Column(
              children: [
                // Back + Title row
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: AppTheme.text),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      'Set your route',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Pickup + Drop fields
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.bg2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Dots + dashed line
                      _buildDotConnector(),
                      const SizedBox(width: 12),
                      // Text fields
                      Expanded(
                        child: Column(
                          children: [
                            // Pickup
                            _buildPickupField(),
                            Divider(
                              height: 1,
                              color: AppTheme.border.withValues(alpha: 0.5),
                            ),
                            // Drop
                            _buildDropField(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Action row: Select on map | Home | Work
                _buildActionRow(),
              ],
            ),
          ),

          // ── Search results or empty state ──
          Expanded(
            child: _searching || _fetchingDetails
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  )
                : _searchResults.isNotEmpty
                    ? _buildSearchResultsList()
                    : _buildEmptyState(),
          ),

          // ── Confirm Route Button ──
          if ((_pickupController.text.isNotEmpty || _pickupIsCurrentLocation) && 
              _dropController.text.isNotEmpty && 
              _searchResults.isEmpty && 
              !_searching)
            _buildConfirmButton(),
        ],
      ),
    );
  }

  /// Green and orange dot with dashed line in between.
  Widget _buildDotConnector() {
    return SizedBox(
      width: 16,
      height: 80,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Green dot (pickup)
          Container(
            width: 12, height: 12,
            decoration: BoxDecoration(
              color: AppTheme.success,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.success.withValues(alpha: 0.4),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          // Dashed line
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final dashHeight = 3.0;
                final dashGap = 3.0;
                final dashCount =
                    (constraints.maxHeight / (dashHeight + dashGap)).floor();
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(dashCount, (_) {
                    return Container(
                      width: 2,
                      height: dashHeight,
                      margin: EdgeInsets.only(bottom: dashGap),
                      color: AppTheme.text3.withValues(alpha: 0.4),
                    );
                  }),
                );
              },
            ),
          ),
          // Orange dot (drop)
          Container(
            width: 12, height: 12,
            decoration: BoxDecoration(
              color: AppTheme.danger,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.danger.withValues(alpha: 0.4),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickupField() {
    return GestureDetector(
      onTap: () {
        setState(() => _activeField = _ActiveField.pickup);
        if (_pickupIsCurrentLocation) {
          _pickupController.clear();
        }
        _pickupFocus.requestFocus();
      },
      behavior: HitTestBehavior.opaque,
      child: AbsorbPointer(
        absorbing: _activeField != _ActiveField.pickup,
        child: TextField(
          controller: _pickupController,
          focusNode: _pickupFocus,
          onChanged: _onSearchChanged,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _pickupIsCurrentLocation && (_pickupController.text == 'Your Location' || _pickupController.text.isEmpty)
                ? AppTheme.success
                : AppTheme.text,
          ),
          decoration: InputDecoration(
            hintText: _pickupIsCurrentLocation
                ? 'Your Current Location'
                : 'Search pickup...',
            hintStyle: GoogleFonts.inter(
              color: _pickupIsCurrentLocation ? AppTheme.success : AppTheme.text3,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            suffixIcon: _activeField == _ActiveField.pickup &&
                    _pickupController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18, color: AppTheme.text3),
                    onPressed: () {
                      _pickupController.clear();
                      _onSearchChanged('');
                    },
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildDropField() {
    return GestureDetector(
      onTap: () {
        setState(() => _activeField = _ActiveField.drop);
        _dropFocus.requestFocus();
      },
      behavior: HitTestBehavior.opaque,
      child: AbsorbPointer(
        absorbing: _activeField != _ActiveField.drop,
        child: TextField(
          controller: _dropController,
          focusNode: _dropFocus,
          onChanged: _onSearchChanged,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.text,
          ),
          decoration: InputDecoration(
            hintText: 'Where are you going?',
            hintStyle: GoogleFonts.inter(
              color: AppTheme.text3,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            suffixIcon: _activeField == _ActiveField.drop &&
                    _dropController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18, color: AppTheme.text3),
                    onPressed: () {
                      _dropController.clear();
                      _onSearchChanged('');
                    },
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildActionRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Select on map
          _buildActionChip(
            icon: Icons.map_outlined,
            label: 'Select on map',
            onTap: _openMapPicker,
          ),
          const SizedBox(width: 10),
          // Home shortcut
          if (widget.savedHome != null)
            _buildActionChip(
              icon: Icons.home_rounded,
              label: 'Home',
              onTap: () => _selectSavedPlace(widget.savedHome!, 'Home'),
            ),
          if (widget.savedHome != null) const SizedBox(width: 10),
          // Work shortcut
          if (widget.savedWork != null)
            _buildActionChip(
              icon: Icons.work_rounded,
              label: 'Work',
              onTap: () => _selectSavedPlace(widget.savedWork!, 'Work'),
            ),
        ],
      ),
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.text2),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _searchResults.length + (_activeField == _ActiveField.pickup ? 1 : 0),
      itemBuilder: (_, i) {
        // Add "Current Location" as first item if searching for pickup
        if (_activeField == _ActiveField.pickup && i == 0) {
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.my_location, size: 20, color: AppTheme.success),
            ),
            title: Text(
              'Your Current Location',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AppTheme.success,
              ),
            ),
            onTap: () async {
              final provider = context.read<RideProvider>();
              final loc = await GoogleMapsService.reverseGeocode(
                widget.currentPosition.latitude,
                widget.currentPosition.longitude,
              );
              provider.setPickup(loc);
              _pickupController.text = 'Your Location';
              _pickupIsCurrentLocation = true;
              setState(() => _searchResults = []);
              _dropFocus.requestFocus();
              _activeField = _ActiveField.drop;
            },
          );
        }

        final r = _searchResults[_activeField == _ActiveField.pickup ? i - 1 : i];
        return Column(
          children: [
            if (i > 0 || _activeField == _ActiveField.drop)
              const Divider(height: 1, indent: 68, color: AppTheme.border),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.bg2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  size: 20,
                  color: AppTheme.text2,
                ),
              ),
              title: Text(
                r.primaryText,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppTheme.text,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                r.secondaryText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: AppTheme.text3,
                  fontSize: 12,
                ),
              ),
              onTap: () async {
                setState(() => _fetchingDetails = true);
                final location = await GoogleMapsService.getPlaceDetails(r.placeId);
                if (mounted) {
                  setState(() => _fetchingDetails = false);
                  if (location != null) _selectLocation(location);
                }
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    // Show a subtle hint when no search is active
    final hasActiveText = _activeField == _ActiveField.drop
        ? _dropController.text.isNotEmpty
        : _pickupController.text.isNotEmpty;

    if (hasActiveText) {
      // User typed something but no results yet — could be debouncing
      return const SizedBox.shrink();
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_rounded,
            size: 64,
            color: AppTheme.text3.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'Search for a destination',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppTheme.text3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Type a place name or address above',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.text3.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmButton() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: () {
          final provider = context.read<RideProvider>();
          if (provider.pickup != null && provider.drop != null) {
            Navigator.pop(context, true);
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: Text(
          'Confirm Route',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
