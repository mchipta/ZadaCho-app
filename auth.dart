import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'legal.dart';
import 'state.dart';
import 'theme.dart';
import 'util.dart';
import 'widgets.dart';

enum AMode { login, reg, regCode, reset, resetCode }

/// Страна для номера телефона: флаг, код, длина номера без кода и разбивка на группы
class Country {
  final String name, flag, code;
  final int len;
  final List<int> groups;
  final String example;
  const Country(this.name, this.flag, this.code, this.len, this.groups, this.example);
}

const kCountries = <Country>[
  Country('Россия', '🇷🇺', '7', 10, [3, 3, 2, 2], '(900) 000-00-00'),
  Country('Беларусь', '🇧🇾', '375', 9, [2, 3, 2, 2], '(29) 123-45-67'),
  Country('Казахстан', '🇰🇿', '7', 10, [3, 3, 2, 2], '(700) 000-00-00'),
  Country('Узбекистан', '🇺🇿', '998', 9, [2, 3, 2, 2], '(90) 123-45-67'),
];

/// Национальная часть номера без кода страны; понимает вставку «+7…», «8…», «+375…»
String _nat(String v, Country c) {
  var d = v.replaceAll(RegExp(r'\D'), '');
  if (c.code == '7') {
    if (d.length > c.len && (d.startsWith('7') || d.startsWith('8'))) d = d.substring(1);
  } else if (d.startsWith(c.code) && d.length > c.len) {
    d = d.substring(c.code.length);
  }
  return d.length > c.len ? d.substring(0, c.len) : d;
}

String _mask(String d, List<int> g) {
  final b = StringBuffer();
  var i = 0;
  for (var k = 0; k < g.length && i < d.length; k++) {
    final end = i + g[k] > d.length ? d.length : i + g[k];
    final part = d.substring(i, end);
    if (k == 0) {
      b.write('($part');
      if (part.length == g[0]) b.write(')');
    } else {
      b.write(k == 1 ? ' ' : '-');
      b.write(part);
    }
    i = end;
  }
  return b.toString();
}

class _PhoneMask extends TextInputFormatter {
  final Country c;
  const _PhoneMask(this.c);
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) {
    var d = _nat(n.text, c);
    final od = o.text.replaceAll(RegExp(r'\D'), '');
    final nd = n.text.replaceAll(RegExp(r'\D'), '');
    // стёрли только скобку или дефис: убираем и последнюю цифру, чтобы удаление не «застревало»
    if (n.text.length < o.text.length && nd == od && d.isNotEmpty) d = d.substring(0, d.length - 1);
    final t = _mask(d, c.groups);
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  AMode m = AMode.login;
  final name = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final pass = TextEditingController();
  final code = TextEditingController();
  Country country = kCountries.first;
  bool busy = false;
  bool show = false;
  String? err;
  String? info;

  late final TapGestureRecognizer _rOffer = TapGestureRecognizer()..onTap = () => openLegal(context, 'offer');
  late final TapGestureRecognizer _rPrivacy = TapGestureRecognizer()..onTap = () => openLegal(context, 'privacy');
  late final TapGestureRecognizer _rConsent = TapGestureRecognizer()..onTap = () => openLegal(context, 'consent');

  Set<String> _soc = {}; // способы входа, включённые на сервере

  void _pwTick() {
    if (mounted && (m == AMode.reg || m == AMode.resetCode)) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    pass.addListener(_pwTick);
    Api.oauthProviders().then((v) {
      if (mounted) setState(() => _soc = v);
    });
  }

  // Логотипы Яндекса и VK рисуются из SVG, чтобы не зависеть от файлов
  static const _yaSvg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 28 28"><circle cx="14" cy="14" r="14" fill="#fc3f1d"/><path d="M15.4 7.4v13.2M15.4 7.4h-2.7a3.3 3.3 0 0 0 0 6.6h2.7M12.9 14l-3.2 6.6" fill="none" stroke="#fff" stroke-width="2.3" stroke-linejoin="round"/></svg>';
  static const _vkSvg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect width="24" height="24" rx="7" fill="#0077ff"/><path transform="translate(3.6 3.6) scale(0.7)" fill="#fff" d="M12.8 17.1c-5.9 0-9.3-4-9.4-10.7h3c.1 4.9 2.3 7 4 7.4V6.4h2.8v4.2c1.7-.2 3.5-2.1 4.1-4.2h2.8c-.5 2.6-2.4 4.5-3.7 5.3 1.3.6 3.4 2.3 4.2 5.4h-3.1c-.7-2.1-2.3-3.7-4.3-3.9v3.9z"/></svg>';

  Widget _socBtn(Pal p, String k, String label, String svg) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => launchUrl(Uri.parse('https://zadacho.ru/oauth/$k/start?mode=app'), mode: LaunchMode.externalApplication),
        child: Container(
          height: 54,
          decoration: BoxDecoration(color: p.bg2, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.bd, width: 1.5)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SvgPicture.string(svg, width: 28, height: 28),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(color: p.tx, fontWeight: FontWeight.w700, fontSize: 15.5)),
          ]),
        ),
      );

  /// Яндекс и VK в один ряд (если на сервере включён только один способ, кнопка на всю ширину)
  Widget _socRow(Pal p) {
    final b = <Widget>[
      if (_soc.contains('yandex')) _socBtn(p, 'yandex', 'Яндекс', _yaSvg),
      if (_soc.contains('vk')) _socBtn(p, 'vk', 'VK ID', _vkSvg),
    ];
    return Row(children: [
      for (var i = 0; i < b.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(child: b[i]),
      ],
    ]);
  }

  @override
  void dispose() {
    _rOffer.dispose();
    _rPrivacy.dispose();
    _rConsent.dispose();
    super.dispose();
  }

  // Ссылка в мелком тексте под кнопками: серая, подчёркнутая (согласие даётся нажатием кнопки)
  TextSpan _ulink(Pal p, String t, GestureRecognizer r) =>
      TextSpan(text: t, recognizer: r, style: TextStyle(color: p.mu, decoration: TextDecoration.underline, decorationColor: p.mu));

  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  String get _em => email.text.trim().toLowerCase();

  void _mode(AMode x) {
    setState(() {
      m = x;
      err = null;
      info = null;
    });
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      busy = true;
      err = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => err = S.i.fail(e));
    }
    if (mounted) setState(() => busy = false);
  }

  bool _check(bool ok, String msg) {
    if (!ok) setState(() => err = msg);
    return ok;
  }

  Future<void> _submit() async {
    switch (m) {
      case AMode.login:
        final id = email.text.trim();
        final byMail = id.contains('@');
        if (!_check(byMail ? _emailRe.hasMatch(_em) : normPhone(id).length >= 11 && normPhone(id).length <= 15, 'Введите почту или номер телефона')) return;
        if (!_check(pass.text.isNotEmpty, 'Введите пароль')) return;
        await _run(() async {
          final Map<String, dynamic> j;
          if (byMail) {
            j = await Api.call('login', {'login': _em, 'hash': sha256Hex('$_em:${pass.text}')});
          } else {
            // вход по номеру: сервер сам находит аккаунт и считает хеш
            j = await Api.call('login', {'login': normPhone(id), 'pw': pass.text, 'hash': ''});
          }
          await _finish(j);
        });
        break;
      case AMode.reg:
        final nat = _nat(phone.text, country);
        if (!_check(name.text.trim().length >= 2, 'Введите имя')) return;
        if (!_check(nat.length == country.len, 'Укажите номер телефона полностью')) return;
        if (!_check(_emailRe.hasMatch(_em), 'Укажите настоящий адрес почты')) return;
        if (!_check(pass.text.length >= 6, 'Пароль — не короче 6 символов')) return;
        await _run(() async {
          await Api.call('sendCode', {'email': _em, 'kind': 'reg'});
          code.clear();
          if (mounted) toast(context, 'Код отправлен. Проверьте почту $_em');
          setState(() {
            m = AMode.regCode;
            info = 'Код отправлен на $_em.\nЕсли письмо не приходит, проверьте папку «Спам».';
          });
        });
        break;
      case AMode.regCode:
        if (!_check(code.text.trim().length >= 4, 'Введите код из письма')) return;
        await _run(() async {
          final j = await Api.call('reg', {
            'login': _em,
            'hash': sha256Hex('$_em:${pass.text}'),
            'name': name.text.trim(),
            'phone': '+${country.code} ${_nat(phone.text, country)}', // как на сайте: «+375 291234567»
            'code': code.text.trim(),
            // согласие даётся нажатием кнопки под текстом с ссылками; сервер сохраняет отметку и редакцию документов
            'terms': 1,
            'pd': 1,
            'docs': kLegalVersion,
          });
          await _finish(j);
        });
        break;
      case AMode.reset:
        if (!_check(_emailRe.hasMatch(_em), 'Укажите почту аккаунта')) return;
        await _run(() async {
          await Api.call('sendCode', {'email': _em, 'kind': 'reset'});
          code.clear();
          pass.clear();
          if (mounted) toast(context, 'Код отправлен. Проверьте почту $_em');
          setState(() {
            m = AMode.resetCode;
            info = 'Если такой аккаунт есть, код отправлен на $_em.\nЕсли письмо не приходит, проверьте папку «Спам».';
          });
        });
        break;
      case AMode.resetCode:
        if (!_check(code.text.trim().length >= 4, 'Введите код из письма')) return;
        if (!_check(pass.text.length >= 6, 'Пароль — не короче 6 символов')) return;
        await _run(() async {
          await Api.call('reset', {
            'email': _em,
            'code': code.text.trim(),
            'hash': sha256Hex('$_em:${pass.text}'),
          });
          pass.clear();
          setState(() {
            m = AMode.login;
            info = 'Пароль изменён. Теперь войдите с новым паролем';
          });
        });
        break;
    }
  }

  Future<void> _finish(Map<String, dynamic> j) async {
    await S.i.setUser(j);
    S.i.loadAds();
    if (mounted) {
      toast(context, 'Добро пожаловать, ${S.i.name}!');
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final titles = {
      AMode.login: 'Войти',
      AMode.reg: 'Создать аккаунт',
      AMode.regCode: 'Регистрация',
      AMode.reset: 'Сброс пароля',
      AMode.resetCode: 'Новый пароль',
    };
    final btn = {
      AMode.login: 'Войти',
      AMode.reg: 'Получить код',
      AMode.regCode: 'Создать аккаунт',
      AMode.reset: 'Получить код',
      AMode.resetCode: 'Сохранить пароль',
    };
    final isCode = m == AMode.regCode || m == AMode.resetCode;
    final v3 = m == AMode.login || m == AMode.reg; // новый вид входа и регистрации (как на сайте)
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SmoothSwitch(
          child: ListView(
            key: ValueKey(m),padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          Align(alignment: Alignment.centerLeft, child: isCode ? const AuthTile(Icons.mail_outline_rounded) : const Logo(size: 48)),
          SizedBox(height: v3 ? 22 : 16),
          Text(titles[m]!, style: TextStyle(fontSize: v3 ? 28 : 26, fontWeight: FontWeight.w800, height: v3 ? 1.15 : null, color: p.tx)),
          SizedBox(height: v3 ? 10 : 6),
          if (isCode)
            Text.rich(
              TextSpan(style: TextStyle(color: p.mu, fontSize: 15, height: 1.5), children: [
                TextSpan(text: m == AMode.regCode ? 'Остался один шаг. Отправили 6 цифр на ' : 'Отправили 6 цифр на '),
                WidgetSpan(alignment: PlaceholderAlignment.middle, child: MailChip(_em)),
                TextSpan(text: m == AMode.regCode ? '. Он действует 10 минут.' : '. Введите код и придумайте новый пароль.'),
              ]),
            )
          else
            Text(
                m == AMode.login
                    ? 'Чтобы откликаться и публиковать объявления'
                    : m == AMode.reg
                        ? 'Займёт минуту. Код придёт на почту'
                        : 'Пришлём код на вашу почту',
                style: TextStyle(color: p.mu, fontSize: v3 ? 15.5 : 15, height: v3 ? 1.45 : null)),
          SizedBox(height: v3 ? 26 : 20),
          if (m == AMode.reg) ...[
            _field(name, 'Имя', cap: TextCapitalization.words),
            _phoneRow(p),
          ],
          if (!isCode)
            _field(email, m == AMode.login ? 'Почта или телефон' : 'Почта', icon: Icons.mail_outline, type: TextInputType.emailAddress),
          if (isCode) Padding(padding: const EdgeInsets.only(bottom: 4), child: OtpField(controller: code, autofocus: true)),
          if (isCode) ResendLink(onResend: () => Api.call('sendCode', {'email': _em, 'kind': m == AMode.regCode ? 'reg' : 'reset'})),
          if (isCode) const Padding(padding: EdgeInsets.only(bottom: 14), child: SpamNote()),
          if (m == AMode.login || m == AMode.reg || m == AMode.resetCode) ...[
            _field(pass, m == AMode.resetCode ? 'Новый пароль' : (m == AMode.reg ? 'Пароль, от 6 символов' : 'Пароль'), icon: Icons.lock_outline, secret: true),
            if (m == AMode.reg || m == AMode.resetCode) PwStrength(pass.text),
          ],
          if (m == AMode.login)
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _mode(AMode.reset),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 2, 16),
                  child: Text('Забыли пароль?', style: TextStyle(color: p.ac, fontWeight: FontWeight.w600, fontSize: 14.5)),
                ),
              ),
            ),
          if (info != null && !isCode) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(info!, style: TextStyle(color: p.ok, fontWeight: FontWeight.w600))),
          if (err != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(err!, style: TextStyle(color: p.dng, fontWeight: FontWeight.w600))),
          GradBtn(btn[m]!, busy: busy, onTap: _submit, height: (isCode || v3) ? 56 : 46, radius: (isCode || v3) ? 16 : 12),
          if (v3) ...[
            if (_soc.isNotEmpty) ...[
              const SizedBox(height: 22),
              Row(children: [
                Expanded(child: Divider(color: p.bd)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(m == AMode.login ? 'или войти через' : 'или', style: TextStyle(color: p.mu, fontSize: 13))),
                Expanded(child: Divider(color: p.bd)),
              ]),
              const SizedBox(height: 16),
              _socRow(p),
            ],
            const SizedBox(height: 14),
            Center(
              child: TextButton(
                onPressed: () => _mode(m == AMode.login ? AMode.reg : AMode.login),
                child: Text.rich(TextSpan(style: TextStyle(color: p.mu, fontSize: 15), children: [
                  TextSpan(text: m == AMode.login ? 'Нет аккаунта? ' : 'Уже есть аккаунт? '),
                  TextSpan(text: m == AMode.login ? 'Создать' : 'Войти', style: TextStyle(color: p.ac, fontWeight: FontWeight.w700)),
                ])),
              ),
            ),
            // условия спрятаны в мелкий текст внизу; согласие даётся нажатием кнопки
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Text.rich(
                TextSpan(
                  style: TextStyle(color: p.mu, fontSize: 12.5, height: 1.45),
                  children: m == AMode.login
                      ? <InlineSpan>[
                          const TextSpan(text: 'Входя, вы принимаете '),
                          _ulink(p, 'условия использования', _rOffer),
                          const TextSpan(text: ' и '),
                          _ulink(p, 'политику конфиденциальности', _rPrivacy),
                        ]
                      : <InlineSpan>[
                          const TextSpan(text: 'Продолжая, вы подтверждаете, что вам есть 18 лет, принимаете '),
                          _ulink(p, 'условия использования', _rOffer),
                          const TextSpan(text: ' и '),
                          _ulink(p, 'политику конфиденциальности', _rPrivacy),
                          const TextSpan(text: ' и даёте '),
                          _ulink(p, 'согласие на обработку данных', _rConsent),
                        ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ] else if (isCode) ...[
            const SizedBox(height: 10),
            Center(child: TextButton(onPressed: () => _mode(m == AMode.regCode ? AMode.reg : AMode.reset), child: Text('Изменить почту', style: TextStyle(color: p.mu, fontWeight: FontWeight.w600)))),
          ] else ...[
            const SizedBox(height: 10),
            Center(child: TextButton(onPressed: () => _mode(AMode.login), child: Text('Назад ко входу', style: TextStyle(color: p.ac, fontWeight: FontWeight.w700)))),
          ],
        ]),
        ),
      ),
    );
  }

  void _setCountry(Country c) {
    final nat = _nat(phone.text, country);
    setState(() {
      country = c;
      phone.text = _mask(_nat(nat, c), c.groups);
    });
  }

  Future<void> _pickCountry() async {
    final p = pal(context);
    FocusScope.of(context).unfocus();
    final c = await showModalBottomSheet<Country>(
      context: context,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Text('Страна номера', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.tx)),
          const SizedBox(height: 6),
          for (final k in kCountries)
            ListTile(
              leading: Text(k.flag, style: const TextStyle(fontSize: 28)),
              title: Text(k.name,
                  style: TextStyle(fontSize: 16, fontWeight: k.name == country.name ? FontWeight.w800 : FontWeight.w600, color: k.name == country.name ? p.ac : p.tx)),
              trailing: Text('+${k.code}', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: k.name == country.name ? p.ac : p.mu)),
              onTap: () => Navigator.pop(ctx, k),
            ),
          const SizedBox(height: 6),
        ]),
      ),
    );
    if (c != null) _setCountry(c);
  }

  Widget _phoneRow(Pal p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: _pickCountry,
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: p.bg2, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.bd, width: 1.5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(country.flag, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 6),
              Text('+${country.code}', style: TextStyle(color: p.tx, fontWeight: FontWeight.w700, fontSize: 15.5)),
              Icon(Icons.keyboard_arrow_down_rounded, color: p.mu),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            contextMenuBuilder: appContextMenu,
            controller: phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [_PhoneMask(country)],
            autocorrect: false,
            style: TextStyle(color: p.tx),
            decoration: _dec(p, 'Телефон', hint: country.example).copyWith(constraints: const BoxConstraints(minHeight: 60)),
          ),
        ),
      ]),
    );
  }

  /// Поле входа и регистрации: плавающая подпись, фон чуть темнее карточки, скругление 16
  InputDecoration _dec(Pal p, String label, {String? hint, Widget? suffix}) {
    OutlineInputBorder ob(Color c, [double w = 1.5]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: suffix,
      filled: true,
      fillColor: p.bg2,
      labelStyle: TextStyle(color: p.mu),
      hintStyle: TextStyle(color: p.mu.withOpacity(.7)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      enabledBorder: ob(p.bd),
      border: ob(p.bd),
      focusedBorder: ob(p.ac, 1.8),
    );
  }

  Widget _field(TextEditingController c, String label,
      {IconData? icon, bool secret = false, TextInputType? type, String? hint, TextCapitalization cap = TextCapitalization.none}) {
    final p = pal(context);
    final v3 = m == AMode.login || m == AMode.reg;
    final eye = secret
        ? IconButton(
            icon: Icon(show ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: p.mu),
            onPressed: () { setState(() => show = !show); })
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(contextMenuBuilder: appContextMenu,
        controller: c,
        obscureText: secret && !show,
        keyboardType: type,
        textCapitalization: cap,
        autocorrect: false,
        enableSuggestions: !secret,
        style: TextStyle(color: p.tx),
        decoration: v3
            ? _dec(p, label, hint: hint, suffix: eye)
            : deco(context, label, hint: hint, prefix: icon == null ? null : Icon(icon, color: p.mu), suffix: eye),
      ),
    );
  }
}

// Заглушка для экранов, которые доступны только после входа
class NeedAuth extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const NeedAuth({super.key, required this.icon, required this.title, required this.text});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: p.bg2, shape: BoxShape.circle, border: Border.all(color: p.bd)),
            child: Icon(icon, size: 38, color: p.ac),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.tx)),
          const SizedBox(height: 6),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: p.mu, fontSize: 15)),
          const SizedBox(height: 20),
          SizedBox(
            width: 260,
            child: GradBtn('Войти или создать аккаунт',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthPage()))),
          ),
        ]),
      ),
    );
  }
}
