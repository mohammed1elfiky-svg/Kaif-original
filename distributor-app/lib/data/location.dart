import 'package:geolocator/geolocator.dart';

/// Current GPS position for the customer visits. GPS works without a network; returns null when
/// location is off, not permitted or not found in time, so a visit never blocks the work.
Future<({double latitude, double longitude})?> currentLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) return null;
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
  try {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
    );
    return (latitude: p.latitude, longitude: p.longitude);
  } catch (_) {
    final last = await Geolocator.getLastKnownPosition();
    return last == null ? null : (latitude: last.latitude, longitude: last.longitude);
  }
}
