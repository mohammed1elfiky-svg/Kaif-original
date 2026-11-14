import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Connection and printer settings of the device. The password is kept in the encrypted
/// storage of the phone (Android Keystore), the rest in the app preferences.
class Settings {
  final SharedPreferences prefs;
  final FlutterSecureStorage secure;
  String _password;

  Settings(this.prefs, this.secure, this._password);

  static Future<Settings> load({FlutterSecureStorage? secure}) async {
    final prefs = await SharedPreferences.getInstance();
    final storage = secure ?? const FlutterSecureStorage();
    var password = await storage.read(key: 'password') ?? '';
    // passwords saved in plain text by the first version of the app are moved to the encrypted storage
    final old = prefs.getString('password');
    if (old != null) {
      if (password.isEmpty) {
        password = old;
        await storage.write(key: 'password', value: old);
      }
      await prefs.remove('password');
    }
    return Settings(prefs, storage, password);
  }

  String get server => prefs.getString('server') ?? '';
  String get user => prefs.getString('user') ?? '';
  String get password => _password;
  String get printerMac => prefs.getString('printerMac') ?? '';
  String get printerName => prefs.getString('printerName') ?? '';
  int get paperMm => prefs.getInt('paperMm') ?? 80;

  bool get loggedIn => server.isNotEmpty && user.isNotEmpty;

  Future<void> setLogin(String server, String user, String password) async {
    await prefs.setString('server', server.trim());
    await prefs.setString('user', user.trim());
    await secure.write(key: 'password', value: password);
    _password = password;
  }

  Future<void> logout() async {
    await secure.delete(key: 'password');
    _password = '';
    await prefs.remove('user');
  }

  Future<void> setPrinter(String mac, String name) async {
    await prefs.setString('printerMac', mac);
    await prefs.setString('printerName', name);
  }

  Future<void> setPaper(int mm) => prefs.setInt('paperMm', mm);
}
