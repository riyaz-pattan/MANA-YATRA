import 'package:flutter/material.dart';
import '../widgets/moving_vehicle_loader.dart';

class CustomSplashScreen extends StatelessWidget {
  const CustomSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: MovingVehicleLoader(text: ''),
      ),
    );
  }
}
