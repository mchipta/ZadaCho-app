import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'state.dart';
import 'theme.dart';
import 'util.dart';
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

  bool _askingPhone = false;

  // Сервис входа (VK, Яндекс) мог не передать телефон: просим указать его, без номера аккаунт не оставляем
  Future<void> _checkPhone() async {
    if (_askingPhone || !mounted || !S.i.logged) return;
    if (digitsOnly(S.i.phone).length >= 8) return;
    _askingPhone = true;
    try {
      await showDialog<void>(context: context, barrierDismissible: false, builder: (c) => const _PhoneAsk());
    } finally {
      _askingPhone = false;
    }
  }

  Future<void> _check() async {
    await _checkOauth();
    await _checkPhone();
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


class _PhoneAsk extends StatefulWidget {
  const _PhoneAsk();
  @override
  State<_PhoneAsk> createState() => _PhoneAskState();
}

class _PhoneAskState extends State<_PhoneAsk> {
  final _c = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = normPhone(_c.text);
    if (!phoneComplete(n)) {
      setState(() => _err = 'Введите номер телефона полностью');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final j = await Api.call('chPhone', {'phone': '+$n'});
      await S.i.patchUser({'phone': j['phone']});
      if (mounted) {
        Navigator.pop(context);
        toast(context, 'Номер сохранён');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = S.i.fail(e);
        });
      }
    }
  }

  Future<void> _out() async {
    await S.i.setUser(null);
    S.i.loadAds();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: p.card,
        title: Text('Укажите номер телефона', style: TextStyle(color: p.tx, fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Сервис входа не передал ваш номер. Укажите его, чтобы с вами могли связаться по объявлениям.', style: TextStyle(color: p.mu)),
            ),
            TextField(
              controller: _c,
              autofocus: true,
              keyboardType: TextInputType.phone,
              inputFormatters: [PhoneFormatter()],
              decoration: InputDecoration(labelText: 'Номер телефона', hintText: '+7 (900) 000-00-00', errorText: _err),
              onSubmitted: (_) => _busy ? null : _save(),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : _out, child: const Text('Выйти из аккаунта')),
          FilledButton(onPressed: _busy ? null : _save, child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Сохранить')),
        ],
      ),
    );
  }
}
