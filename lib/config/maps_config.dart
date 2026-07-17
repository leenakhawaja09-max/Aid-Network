/// Google Maps / Directions API key.
///
/// Prefer not committing real keys: use
/// `flutter run --dart-define=GOOGLE_MAPS_API_KEY=your_key`
/// and restrict the key (HTTP referrers for web, Android/iOS app restrictions)
/// in Google Cloud Console.
const String googleMapsApiKey = String.fromEnvironment(
  'GOOGLE_MAPS_API_KEY',
  defaultValue: 'AIzaSyBQ1vqPT6uX0EeeTh-DeKd87reurG4XHXQ',
);
