import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'settings.dart';
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
    final lk = q['linked'];
    if (lk != null && lk.isNotEmpty) { // Яндекс/VK привязан к уже вошедшему аккаунту
      toast(context, '${lk == 'vk' ? 'VK ID' : 'Яндекс ID'} привязан');
      _openAcc();
      return;
    }
    if (err != null && err.isNotEmpty) {
      toast(context, err);
      if (q['link'] == '1') _openAcc();
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

  void _openAcc() {
    if (!S.i.logged || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsSectionPage(section: 'acc', title: 'Вход и пароль')));
  }

  bool _askingPhone = false;

  // Сервис входа (VK, Яндекс) мог не передать телефон: просим указать его, без номера аккаунт не оставляем
  Future<void> _checkPhone() async {
    if (_askingPhone || !mounted || !S.i.logged) return;
    if (digitsOnly(S.i.phone).length >= 8) return;
    _askingPhone = true;
    try {
      if (MediaQuery.of(context).size.width >= 720) {
        await showDialog<void>(context: context, barrierDismissible: false, builder: (c) => const _PhoneAsk(wide: true));
      } else {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          isDismissible: false,
          enableDrag: false,
          backgroundColor: pal(context).card,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          builder: (c) => const _PhoneAsk(),
        );
      }
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
  final bool wide;
  const _PhoneAsk({this.wide = false});
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
    final mq = MediaQuery.of(context);
    OutlineInputBorder ob(Color c) => OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c, width: 1.5));
    final content = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, widget.wide ? 28 : 10, 20, 22 + (widget.wide ? 0 : mq.padding.bottom)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (!widget.wide) Center(child: Container(width: 40, height: 5, margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(color: p.bd, borderRadius: BorderRadius.circular(3)))),
        const AuthTile(Icons.smartphone_rounded),
        const SizedBox(height: 16),
        Text('Укажите номер телефона', style: TextStyle(color: p.tx, fontSize: 26, height: 1.15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('Сервис входа не передал ваш номер. Укажите его, чтобы с вами могли связаться по объявлениям.', style: TextStyle(color: p.mu, fontSize: 15, height: 1.5)),
        const SizedBox(height: 18),
        TextField(
          controller: _c,
          autofocus: true,
          enabled: !_busy,
          keyboardType: TextInputType.phone,
          inputFormatters: [PhoneFormatter()],
          style: TextStyle(color: p.tx, fontSize: 17),
          decoration: InputDecoration(
            labelText: 'Номер телефона',
            hintText: '+7 (900) 000-00-00',
            hintStyle: TextStyle(color: p.mu.withOpacity(.7)),
            filled: true,
            fillColor: p.bg2,
            labelStyle: TextStyle(color: p.mu),
            floatingLabelStyle: TextStyle(color: p.ac),
            contentPadding: const EdgeInsets.fromLTRB(16, 20, 12, 18),
            enabledBorder: ob(p.bd),
            border: ob(p.bd),
            focusedBorder: ob(p.ac),
          ),
          onSubmitted: (_) => _busy ? null : _save(),
        ),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: TextStyle(color: p.dng, fontSize: 13.5, fontWeight: FontWeight.w600))),
        const SizedBox(height: 20),
        GradBtn('Сохранить', busy: _busy, height: 56, radius: 16, onTap: _busy ? null : _save),
        const SizedBox(height: 6),
        SizedBox(width: double.infinity, height: 48, child: TextButton(style: TextButton.styleFrom(alignment: Alignment.center, padding: EdgeInsets.zero), onPressed: _busy ? null : _out, child: Center(child: Text('Выйти из аккаунта', textAlign: TextAlign.center, style: TextStyle(color: p.mu, fontSize: 15, fontWeight: FontWeight.w600))))),
      ]),
    );
    return PopScope(
      canPop: false,
      child: widget.wide
          ? Dialog(
              backgroundColor: p.card,
              insetPadding: const EdgeInsets.all(24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: content),
            )
          : Padding(padding: EdgeInsets.only(bottom: mq.viewInsets.bottom), child: content),
    );
  }
}
