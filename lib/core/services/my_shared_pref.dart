import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class MySharedPref {
  static const tokenSaver = 'tokenSaver';
  static const roleSaver = 'roleSaver';

  SharedPreferences? _sp;
  Completer<void>? _initCompleter;

  Future<void> _ensureInitialized() async {
    if (_sp != null) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();
    try {
      _sp = await SharedPreferences.getInstance();
      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.completeError(e);
    }
  }

  bool get isReady => _sp != null;

  Future<void> initialize() async {
    await _ensureInitialized();
  }

  T? read<T>(String key) {
    if (_sp == null) return null;
    var value = _sp!.get(key);
    if (value == null) {
      return null;
    }
    return value as T;
  }

  Future<bool> write<T>(String key, T value) async {
    await _ensureInitialized();
    if (value is String) {
      return await _sp!.setString(key, value);
    } else if (value is bool) {
      return await _sp!.setBool(key, value);
    }
    return false;
  }

  Future<bool> remove(String key) async {
    await _ensureInitialized();
    return await _sp!.remove(key);
  }

  Future<bool> saveUserToken(String token) async {
    await _ensureInitialized();
    return await _sp!.setString(tokenSaver, token);
  }

  Future<bool> saveUserRole(String role) async {
    await _ensureInitialized();
    return await _sp!.setString(roleSaver, role);
  }

  String? getUserRole() {
    if (_sp == null) return null;
    return _sp!.getString(roleSaver);
  }

  String? getUserToken() {
    if (_sp == null) return null;
    return _sp!.getString(tokenSaver);
  }

  Future<bool> removeUserTokenWthRole() async {
    await _ensureInitialized();
    await _sp!.remove(tokenSaver);
    await _sp!.remove(roleSaver);
    return true;
  }
}
