import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'state.dart';
import 'widgets.dart';

// Ярлыки при долгом нажатии на значок приложения: «Разместить», «Поиск», «Сообщения»
class ShortcutHost extends StatefulWidget {
  final Widget child;
  const ShortcutHost({super.key, required this.child});
  @override
  State<ShortcutHost> createState() => _ShortcutHostState();
}

class _ShortcutHostState extends State<ShortcutHost> with WidgetsBindingObserver {
  static const _ch = MethodChannel('ru.zadacho.app/shortcut');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  // Возврат из браузера после входа через Яндекс ID / VK ID
  Future<void> _checkOauth() async {
    String? link;
    try {
      link = await _ch.invokeMethod<String>('takeOauth');
    } catch (_) {
      return;
    }
    if (link == null || !mounted) return;
    final q = Uri.parse(link).queryParameters;
    Navigator.of(context).popUntil((r) => r.isFirst);
    final err = q['err'];
    if (err != null && err.isNotEmpty) {
      toast(context, err);
      return;
    }
    final tk = q['ticket'];
    if (tk == null || tk.isEmpty) return;
    try {
      final j = await Api.call('oauthTicket', {'ticket': tk});
      await S.i.setUser(j);
      S.i.loadAds();
      if (mounted) toast(context, 'Добро пожаловать, ${S.i.name}!');
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> _check() async {
    await _checkOauth();
    String? key;
    try {
      key = await _ch.invokeMethod<String>('take');
    } catch (_) {
      return;
    }
    if (key == null || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    switch (key) {
      case 'post':
        if (S.i.logged) {
          S.i.goTab(2);
        } else {
          toast(context, 'Войдите, чтобы разместить объявление');
          S.i.goTab(3);
        }
        break;
      case 'search':
        S.i.goTab(1);
        break;
      case 'messages':
        S.i.goTab(S.i.logged ? 4 : 3);
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
