import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'admin.dart';
import 'api.dart';
import 'info.dart';
import 'legal.dart';
import 'models.dart';
import 'near.dart';
import 'map_page.dart';
import 'messages.dart';
import 'state.dart';
import 'theme.dart';
import 'util.dart';
import 'widgets.dart';

class FieldSpec {
  final String label;
  final String initial;
  final bool secret;
  final bool multi;
  final TextInputType? type;
  final int? maxLen;
  final bool digitsOnly;
  final bool strength; // показывать надёжность пароля
  final int? matchWith; // индекс поля, с которым сверяем («Повторите пароль»)
  final bool otp; // код из письма в 6 клетках
  const FieldSpec(this.label, {this.initial = '', this.secret = false, this.multi = false, this.type, this.maxLen, this.digitsOnly = false, this.strength = false, this.matchWith, this.otp = false});
}

/// Ответ «Назад» из окна шага 2 (см. askFields(back: true))
const kBackMarker = '__back__';

/// Единое окно ввода: на телефоне нижняя шторка, на широком экране — окно по центру (как на сайте).
Future<List<String>?> askFields(BuildContext context, String title, List<FieldSpec> fields,
    {String ok = 'Сохранить',
    String? hint,
    String? chip,
    String? chipAfter,
    IconData? icon,
    int? step,
    bool back = false,
    Future<void> Function(List<String>)? onSubmit,
    Future<void> Function()? resend}) {
  Widget build(bool wide) => _FieldsDialog(
      title: title, fields: fields, ok: ok, hint: hint, chip: chip, chipAfter: chipAfter, icon: icon, step: step, back: back, wide: wide, onSubmit: onSubmit, resend: resend);
  if (MediaQuery.of(context).size.width >= 720) {
    return showDialog<List<String>>(context: context, builder: (c) => build(true));
  }
  final p = pal(context);
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: p.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (c) => build(false),
  );
}

class _FieldsDialog extends StatefulWidget {
  final String title, ok;
  final String? hint, chip, chipAfter;
  final IconData? icon;
  final int? step;
  final bool back, wide;
  final List<FieldSpec> fields;
  final Future<void> Function(List<String>)? onSubmit;
  final Future<void> Function()? resend;
  const _FieldsDialog(
      {required this.title, required this.fields, required this.ok, this.hint, this.chip, this.chipAfter, this.icon, this.step, this.back = false, this.wide = false, this.onSubmit, this.resend});
  @override
  State<_FieldsDialog> createState() => _FieldsDialogState();
}

class _FieldsDialogState extends State<_FieldsDialog> {
  late final List<TextEditingController> cs = [for (final f in widget.fields) TextEditingController(text: f.initial)];
  late final List<bool> _shown = List.filled(widget.fields.length, false);
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    for (final c in cs) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _submit() async {
    final vals = [for (final c in cs) c.text.trim()];
    if (widget.onSubmit == null) {
      Navigator.pop(context, vals);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await widget.onSubmit!(vals);
      if (mounted) Navigator.pop(context, vals);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = S.i.fail(e);
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in cs) {
      c.dispose();
    }
    super.dispose();
  }

  InputDecoration _deco(Pal p, FieldSpec f, int i) {
    OutlineInputBorder ob(Color c, [double w = 1.5]) => OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c, width: w));
    return InputDecoration(
      labelText: f.label,
      filled: true,
      fillColor: p.bg2,
      labelStyle: TextStyle(color: p.mu),
      floatingLabelStyle: TextStyle(color: p.ac),
      counterText: '',
      contentPadding: const EdgeInsets.fromLTRB(16, 20, 12, 18),
      enabledBorder: ob(p.bd),
      border: ob(p.bd),
      focusedBorder: ob(p.ac),
      suffixIcon: f.secret
          ? IconButton(
              icon: Icon(_shown[i] ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: p.mu, size: 22),
              onPressed: () => setState(() => _shown[i] = !_shown[i]))
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final mq = MediaQuery.of(context);
    final hasOtp = widget.fields.any((f) => f.otp);
    final content = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, widget.wide ? 28 : 10, 20, 22 + (widget.wide ? 0 : mq.padding.bottom)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (!widget.wide) Center(child: Container(width: 40, height: 5, margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(color: p.bd, borderRadius: BorderRadius.circular(3)))),
        AuthTile(widget.icon ?? (hasOtp ? Icons.mail_outline_rounded : Icons.edit_outlined)),
        const SizedBox(height: 16),
        Text(widget.title, style: TextStyle(color: p.tx, fontSize: 26, height: 1.15, fontWeight: FontWeight.w800)),
        if (widget.hint != null) ...[
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(style: TextStyle(color: p.mu, fontSize: 15, height: 1.5), children: [
              TextSpan(text: widget.hint!),
              if (widget.chip != null) ...[
                const TextSpan(text: ' '),
                WidgetSpan(alignment: PlaceholderAlignment.middle, child: MailChip(widget.chip!)),
              ],
              if (widget.chipAfter != null) TextSpan(text: widget.chipAfter!),
            ]),
          ),
        ],
        if (widget.step != null) StepBar(widget.step!),
        SizedBox(height: widget.step != null ? 6 : 18),
        for (var i = 0; i < widget.fields.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: widget.fields[i].otp ? 0 : 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (widget.fields[i].otp)
                Padding(padding: const EdgeInsets.only(top: 12), child: OtpField(controller: cs[i], enabled: !_busy, autofocus: true))
              else
                TextField(
                  contextMenuBuilder: appContextMenu,
                  controller: cs[i],
                  obscureText: widget.fields[i].secret && !_shown[i],
                  keyboardType: widget.fields[i].type,
                  enabled: !_busy,
                  maxLength: widget.fields[i].maxLen,
                  inputFormatters: [if (widget.fields[i].digitsOnly) FilteringTextInputFormatter.digitsOnly],
                  minLines: widget.fields[i].multi ? 3 : 1,
                  maxLines: widget.fields[i].multi ? 5 : 1,
                  autocorrect: !widget.fields[i].secret,
                  enableSuggestions: !widget.fields[i].secret,
                  style: TextStyle(color: p.tx, fontSize: 17),
                  decoration: _deco(p, widget.fields[i], i),
                ),
              if (widget.fields[i].strength) Padding(padding: const EdgeInsets.only(top: 10), child: PwStrength(cs[i].text)),
              if (widget.fields[i].matchWith != null) Padding(padding: const EdgeInsets.only(top: 2), child: PwMatch(cs[widget.fields[i].matchWith!].text, cs[i].text)),
            ]),
          ),
        if (widget.resend != null) ResendLink(onResend: widget.resend!),
        if (hasOtp) const SpamNote(),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: TextStyle(color: p.dng, fontSize: 13.5, fontWeight: FontWeight.w600))),
        const SizedBox(height: 20),
        GradBtn(widget.ok, busy: _busy, height: 56, radius: 16, onTap: _busy ? null : _submit),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: TextButton(
            style: TextButton.styleFrom(alignment: Alignment.center, padding: EdgeInsets.zero),
            onPressed: _busy ? null : () => Navigator.pop(context, widget.back ? const [kBackMarker] : null),
            child: Center(child: Text(widget.back ? 'Назад' : 'Отмена', textAlign: TextAlign.center, style: TextStyle(color: p.mu, fontSize: 15, fontWeight: FontWeight.w600))),
          ),
        ),
      ]),
    );
    if (widget.wide) {
      return Dialog(
        backgroundColor: p.card,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: content),
      );
    }
    return Padding(padding: EdgeInsets.only(bottom: mq.viewInsets.bottom), child: content);
  }
}

class SettingsBody extends StatefulWidget {
  final bool profileOnly;
  final String section; // '' — главный экран настроек, иначе раздел: appear, privacy, notif, inn, devices, tz
  const SettingsBody({super.key, this.profileOnly = false, this.section = ''});
  @override
  State<SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<SettingsBody> {
  bool busy = false;
  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  Future<void> _run(Future<void> Function() f) async {
    setState(() => busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) toast(context, S.i.fail(e), err: true);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _avatar() async {
    final has = (S.i.user?['avatar'] ?? '').toString().isNotEmpty;
    final act = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: pal(context).card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Сделать фото'), onTap: () => Navigator.pop(c, 'camera')),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Выбрать из галереи'), onTap: () => Navigator.pop(c, 'gallery')),
          if (has) ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Удалить фото'), onTap: () => Navigator.pop(c, 'remove')),
        ]),
      ),
    );
    if (act == null) return;
    await _run(() async {
      var data = '';
      if (act != 'remove') {
        final x = await ImagePicker().pickImage(
            source: act == 'camera' ? ImageSource.camera : ImageSource.gallery,
            maxWidth: 200,
            maxHeight: 200,
            imageQuality: 60);
        if (x == null) return;
        final bytes = await x.readAsBytes();
        final low = x.path.toLowerCase();
        final mime = low.endsWith('.png') ? 'png' : low.endsWith('.webp') ? 'webp' : 'jpeg';
        data = 'data:image/$mime;base64,${base64Encode(bytes)}';
        if (data.length > 40000) throw ApiError('Фото слишком большое. Выберите другое');
      }
      await Api.call('avatar', {'data': data});
      await S.i.patchUser({'avatar': data});
      if (mounted) toast(context, data.isEmpty ? 'Фото удалено' : 'Фото обновлено');
    });
  }

  Future<void> _name() async {
    final r = await askFields(context, 'Имя', [FieldSpec('Ваше имя', initial: S.i.name)]);
    if (r == null) return;
    await _run(() async {
      final j = await Api.call('chName', {'name': r[0]});
      await S.i.patchUser({'name': j['name']});
      S.i.loadAds();
      if (mounted) toast(context, 'Имя изменено');
    });
  }

  Future<void> _phone() async {
    final r = await askFields(context, 'Телефон', [FieldSpec('Номер телефона', initial: fmtPhone(S.i.phone), type: TextInputType.phone)]);
    if (r == null) return;
    await _run(() async {
      if (!phoneComplete(normPhone(r[0]))) throw ApiError('Введите номер телефона полностью');
      final j = await Api.call('chPhone', {'phone': '+${normPhone(r[0])}'});
      await S.i.patchUser({'phone': j['phone']});
      if (mounted) toast(context, 'Телефон изменён');
    });
  }

  Future<void> _email() async {
    final r = await askFields(context, 'Новая почта', [FieldSpec('Адрес почты', type: TextInputType.emailAddress)],
        ok: 'Получить код', hint: 'Сейчас вы входите с ${S.i.login}. Пришлём код на новый адрес.');
    if (r == null) return;
    final em = r[0].toLowerCase();
    if (!_emailRe.hasMatch(em)) {
      toast(context, 'Укажите настоящий адрес почты');
      return;
    }
    var sent = false;
    await _run(() async {
      await Api.call('sendCode', {'email': em, 'kind': 'chg'});
      sent = true;
    });
    if (!sent || !mounted) return;
    final c = await askFields(
        context,
        'Подтверждение',
        [FieldSpec('Код из письма', type: TextInputType.number), FieldSpec('Текущий пароль', secret: true)],
        ok: 'Изменить',
        resend: () => Api.call('sendCode', {'email': em, 'kind': 'chg'}),
        hint: 'Код отправлен на $em.\nЕсли письмо не приходит, проверьте папку «Спам».');
    if (c == null) return;
    await _run(() async {
      final j = await Api.call('chEmail', {
        'email': em,
        'code': c[0],
        'old': sha256Hex('${S.i.login}:${c[1]}'),
        'hash': sha256Hex('$em:${c[1]}'),
      });
      await S.i.patchUser({'login': j['login'], 'pid': j['pid']});
      if (mounted) toast(context, 'Почта изменена. Теперь входите с $em');
    });
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Выйти')),
        ],
      ),
    );
    if (ok == true) {
      await S.i.setUser(null);
      S.i.loadAds();
      if (mounted) Navigator.pop(context);
    }
  }

  Widget _label(Pal p, String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(t, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: p.tx)),
      );

  // ---------- Главный экран настроек: короткий список разделов с иконками ----------
  Widget _rowsCard(Pal p, List<Widget> rows) => Container(
        decoration: cardDeco(p, r: 20),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: 64, color: p.bd),
            rows[i],
          ],
        ]),
      );

  Widget _cap(Pal p, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 0, 8),
        child: Text(t.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: .6, color: p.mu)),
      );

  Widget _group(Pal p, String title, List<Widget> rows) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_cap(p, title), _rowsCard(p, rows)]);

  Widget _swRow(Pal p, IconData icon, Color k, String title, String sub, bool v, ValueChanged<bool> f) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: k.withOpacity(.16), borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: k, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: p.tx)),
              if (sub.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 1), child: Text(sub, style: TextStyle(color: p.mu, fontSize: 13, height: 1.3))),
            ]),
          ),
          Switch(value: v, activeColor: p.ac, onChanged: f),
        ]),
      );

  Widget _hubRow(Pal p, IconData icon, Color k, String title, String sub, VoidCallback f) {
    return Tap(
      onTap: busy ? null : () { f(); },
      scale: .99,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: k.withOpacity(.16), borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: k, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: k == p.dng ? p.dng : p.tx)),
              if (sub.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.mu, fontSize: 13)),
                ),
            ]),
          ),
          Icon(Icons.chevron_right, color: p.mu),
        ]),
      ),
    );
  }

  void _open(String sec, String title) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsSectionPage(section: sec, title: title)));

  String _zoneName() {
    for (final z in kSiteTimeZones) {
      if (z[0] == S.i.timeZone) return z[1].toString();
    }
    return S.i.timeZone;
  }

  List<Widget> _hubItems(Pal p) {
    final tm = S.i.themeMode;
    final tn = tm == ThemeMode.dark ? 'Тёмная' : (tm == ThemeMode.light ? 'Светлая' : 'Авто');
    final priv = {'all': 'Всем вошедшим', 'reply': 'По откликам', 'chat': 'Только чат'}[S.i.phonePrivacy] ?? 'Всем вошедшим';
    final inn = (S.i.user?['inn'] ?? '').toString();
    final innOk = S.i.user?['innOk'] == true && inn.length == 12;
    final off = S.i.notifTypes.values.where((v) => v == false).length;
    return [
      _group(p, 'Поиск', [
        _hubRow(p, Icons.place_outlined, _cRed, 'Регион для поиска', S.i.regionCity.isEmpty ? 'Все города' : S.i.regionCity,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegionPage()))),
      ]),
      _group(p, 'Внешний вид', [
        _hubRow(p, Icons.palette_outlined, _cPurple, 'Тема и акцент', '$tn · ${Pal.accents[S.i.accentIdx][0]}', () => _open('appear', 'Внешний вид')),
      ]),
      if (S.i.logged)
        _group(p, 'Приватность и безопасность', [
        _hubRow(p, Icons.phonelink_lock_outlined, _cGreen, 'Приватность номера', priv, () => _open('privacy', 'Приватность номера')),
        _hubRow(p, Icons.lock_outline_rounded, _cPurple, 'Вход и пароль', 'Пароль, Яндекс ID, VK ID', () => _open('acc', 'Вход и пароль')),
        _hubRow(p, Icons.devices_outlined, _cBlue, 'Активные устройства', 'Где выполнен вход в аккаунт', () => _open('devices', 'Активные устройства')),
      ]),
      if (S.i.logged)
        _group(p, 'Уведомления', [
        _hubRow(p, Icons.notifications_none_rounded, _cAmber, 'Уведомления и «Не беспокоить»',
            S.i.dndOn ? 'Не беспокоить: ${S.i.dndFrom} – ${S.i.dndTo}' : (off == 0 ? 'Все типы включены' : 'Отключено типов: $off'),
            () => _open('notif', 'Уведомления')),
      ]),
      _group(p, 'Время', [
        _hubRow(p, Icons.schedule_rounded, _cCyan, 'Часовой пояс', S.i.timeZone.isEmpty ? 'Автоматически: ${deviceZoneLabel()}' : _zoneName(),
            () => _open('tz', 'Часовой пояс')),
      ]),
      if (S.i.logged)
        _group(p, 'Мои данные', [
          _hubRow(p, Icons.verified_outlined, _cGreen, 'Статус самозанятого (ИНН)',
              innOk ? 'ИНН подтверждён' : 'Подтвердить для значка доверия', () => _open('inn', 'Самозанятость (ИНН)')),
          ..._dataRows(p),
        ]),
      _group(p, 'Помощь и информация', [
        if (S.i.logged) _hubRow(p, Icons.support_agent_rounded, _cOrange, 'Чат с поддержкой', 'Ответим прямо в приложении', _openSupportSheet),
        _hubRow(p, Icons.description_outlined, _cBlue, 'Документы', 'Оферта, политика, согласие на данные', () => openLegal(context, 'offer')),
        _hubRow(p, Icons.business_center_outlined, _cPurple, 'Для бизнеса', 'Оставить заявку', () => showLeadForm(context)),
        if (S.i.logged && S.i.user?['admin'] == true)
          _hubRow(p, Icons.admin_panel_settings_outlined, p.ac, 'Админ-панель', 'Модерация, жалобы, заявки',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPage()))),
      ]),
      if (S.i.logged)
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Container(
            decoration: cardDeco(p, r: 20),
            clipBehavior: Clip.antiAlias,
            child: _hubRow(p, Icons.logout, p.dng, 'Выйти из аккаунта', '', () => confirmLogout(context)),
          ),
        ),
      const AppStamp(),
    ];
  }

  List<Widget> _sectionItems(Pal p) {
    final sec = widget.section;
    final tm = S.i.themeMode;
    return [
      if (sec == 'appear') ...[
        _cap(p, 'Тема'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: cardDeco(p, r: 20),
          child: Row(children: [
            for (final t in [
              [ThemeMode.dark, 'Тёмная'],
              [ThemeMode.light, 'Светлая'],
              [ThemeMode.system, 'Авто'],
            ])
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: t[0] == ThemeMode.system ? 0 : 8),
                  child: GestureDetector(
                    onTap: () => S.i.setTheme(t[0] as ThemeMode),
                    child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: tm == t[0] ? LinearGradient(colors: [p.ac, p.ac2]) : null,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: tm == t[0] ? Colors.transparent : p.bd),
                      ),
                      child: Text(t[1] as String,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: tm == t[0] ? Colors.white : p.tx)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        _cap(p, 'Цвет акцента'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: cardDeco(p, r: 20),
          child: Row(children: [
            for (var i = 0; i < Pal.accents.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == Pal.accents.length - 1 ? 0 : 8),
                  child: GestureDetector(
                    onTap: () => S.i.setAccent(i),
                    child: Column(children: [
                      Container(
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(colors: [Pal.accents[i][1] as Color, Pal.accents[i][2] as Color], begin: Alignment.topLeft, end: Alignment.bottomRight),
                          border: Border.all(color: S.i.accentIdx == i ? p.tx : Colors.transparent, width: 2),
                        ),
                        child: S.i.accentIdx == i ? const Icon(Icons.check_rounded, size: 22, color: Colors.white) : null,
                      ),
                      const SizedBox(height: 5),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(Pal.accents[i][0] as String,
                            maxLines: 1, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: S.i.accentIdx == i ? p.tx : p.mu)),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
        _cap(p, 'Нижняя панель'),
        _rowsCard(p, [
          _swRow(p, Icons.blur_on_rounded, const Color(0xFF4C8DFF), 'Прозрачная панель', 'Меню становится стеклянным, экран просвечивает',
              S.i.navTransparent, (v) => S.i.setNavTransparent(v)),
        ]),
      ],
      if (sec == 'privacy') ...[
        _privacyCard(p),
          if (S.i.blockedUsers.isNotEmpty) ...[
            _label(p, 'Чёрный список'),
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: cardDeco(p, r: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Заблокированные пользователи не могут писать вам и откликаться на ваши объявления.',
                    style: TextStyle(color: p.mu, fontSize: 12.5)),
                const SizedBox(height: 8),
                for (final entry in S.i.blockedUsers.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Icon(Icons.block_rounded, size: 17, color: p.dng),
                      const SizedBox(width: 8),
                      Expanded(child: Text(entry.value.isEmpty ? 'Пользователь' : entry.value, style: TextStyle(color: p.tx, fontWeight: FontWeight.w700, fontSize: 14))),
                      TextButton(
                        onPressed: () => S.i.setBlocked(entry.key, entry.value, false),
                        child: Text('Разблокировать', style: TextStyle(color: p.ac, fontWeight: FontWeight.w800)),
                      ),
                    ]),
                  ),
              ]),
            ),
          ],
      ],
      if (sec == 'notif') ...[
        _notifCard(p),
          if (S.i.mutedChats.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: cardDeco(p, r: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Уведомления отключены для диалогов', style: TextStyle(color: p.tx, fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 6),
                for (final entry in S.i.mutedChats.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Expanded(child: Text(entry.value.isEmpty ? 'Пользователь' : entry.value, style: TextStyle(color: p.mu, fontSize: 13.5))),
                      TextButton(
                        onPressed: () { S.i.setChatMuted(entry.key, entry.value, false); },
                        child: Text('Включить', style: TextStyle(color: p.ac, fontWeight: FontWeight.w800)),
                      ),
                    ]),
                  ),
              ]),
            ),
      ],
      if (sec == 'inn' && S.i.logged) _innCard(p),
      if (sec == 'acc' && S.i.logged) const _AccountAuthCard(),
      if (sec == 'devices' && S.i.logged) const _DevicesCard(),
      if (sec == 'tz') ...[
        _rowsCard(p, [
          _swRow(p, Icons.schedule_rounded, const Color(0xFF1FB6D4), 'Определять автоматически',
              S.i.timeZone.isEmpty ? 'Сейчас: ${deviceZoneLabel()}' : 'Выбран вручную', S.i.timeZone.isEmpty,
              (on) => S.i.setTimeZone(on ? '' : deviceZoneId())),
        ]),
        if (S.i.timeZone.isNotEmpty) ...[
          const SizedBox(height: 12),
          PickerField(
            label: 'Часовой пояс',
            sheetTitle: 'Часовой пояс',
            value: kSiteTimeZones.any((z) => z[0] == S.i.timeZone) ? S.i.timeZone : '',
            items: [for (final z in kSiteTimeZones.skip(1)) PickItem(z[0], z[1])],
            onChanged: (v) => S.i.setTimeZone(v),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
          child: Text('По часовому поясу показывается время откликов, сообщений и объявлений.', style: TextStyle(color: p.mu, fontSize: 13, height: 1.35)),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: S.i,
      builder: (context, _) {
        final p = pal(context);
        final av = (S.i.user?['avatar'] ?? '').toString();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (busy) LinearProgressIndicator(color: p.ac, backgroundColor: p.bd, minHeight: 3),
          if (widget.profileOnly) GestureDetector(
            onTap: busy ? null : () { _avatar(); },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: cardDeco(p, r: 20),
              child: Row(children: [
                Stack(children: [
                  Avatar(S.i.name, data: av, size: 64),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: p.card, shape: BoxShape.circle, border: Border.all(color: p.bd)),
                      child: Icon(Icons.photo_camera_outlined, size: 15, color: p.ac),
                    ),
                  ),
                ]),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('Нажмите, чтобы сменить фото профиля', style: TextStyle(color: p.ac, fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ),
          if (widget.profileOnly) ...[
            _cap(p, 'Данные профиля'),
            _rowsCard(p, [
              _hubRow(p, Icons.person_outline, const Color(0xFF4C8DFF), 'Имя', S.i.name, _name),
              _hubRow(p, Icons.mail_outline, const Color(0xFFA678FF), 'Почта', S.i.login.contains('@') ? S.i.login : '—', _email),
              _hubRow(p, Icons.call_outlined, p.ok, 'Телефон', S.i.phone.isEmpty ? '—' : fmtPhone(S.i.phone), _phone),
            ]),
          ],
          if (!widget.profileOnly) ...(widget.section.isEmpty ? _hubItems(p) : _sectionItems(p)),
        ]);
      },
    );
  }

  Widget _savedSearchesCard(Pal p) {
    final list = S.i.ss;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: cardDeco(p, r: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.bookmark_outline_rounded, color: p.ac, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Сохранённые поиски (${list.length})', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: p.tx))),
        ]),
        const SizedBox(height: 6),
        if (list.isEmpty)
          Text('Сохраняйте частые запросы в поиске — мы пришлём уведомление о новых объявлениях.', style: TextStyle(color: p.mu, fontSize: 12.5))
        else
          for (final s in list)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      S.i.pendingSearch = s;
                      Navigator.pop(context);
                      S.i.goTab(1);
                    },
                    child: Text(ssLabel(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.tx, fontWeight: FontWeight.w700, fontSize: 13.5)),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, size: 18, color: p.mu),
                  onPressed: () => S.i.delSS(s),
                ),
              ]),
            ),
      ]),
    );
  }

  Widget _privacyCard(Pal p) {
    final cur = S.i.phonePrivacy;
    final opts = const [
      ['all', 'Всем вошедшим', 'Номер виден авторизованным пользователям'],
      ['reply', 'По откликам', 'Номер открывается после отклика на объявление'],
      ['chat', 'Только чат', 'Связь только через сообщения внутри сервиса'],
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: cardDeco(p, r: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < opts.length; i++) ...[
          if (i > 0) Divider(height: 14, color: p.bd),
          Tap(
            onTap: () => S.i.setPhonePrivacy(opts[i][0]),
            scale: .99,
            child: Row(children: [
              Icon(
                cur == opts[i][0] ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: cur == opts[i][0] ? p.ac : p.mu,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(opts[i][1], style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: p.tx)),
                  Text(opts[i][2], style: TextStyle(color: p.mu, fontSize: 12.5)),
                ]),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _notifCard(Pal p) {
    final nt = S.i.notifTypes;
    const blue = Color(0xFF4C8DFF), amber = Color(0xFFF5B301), indigo = Color(0xFF6B6BFF);
    Widget t(String k, IconData i, Color c, String title, String sub) =>
        _swRow(p, i, c, title, sub, nt[k] != false, (v) => S.i.setNotifType(k, v));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _rowsCard(p, [
        _swRow(p, Icons.notifications_none_rounded, amber, 'Push-уведомления', 'Главный переключатель на телефоне',
            S.i.messageNotificationsEnabled, (v) => S.i.setMessageNotificationsEnabled(v)),
      ]),
      _group(p, 'Что присылать', [
        t('msg', Icons.chat_bubble_outline_rounded, blue, 'Новые сообщения', 'Личные сообщения и предложения задач'),
        t('reply', Icons.check_rounded, p.ac, 'Отклики на объявления', 'Новые отклики и смена статуса'),
        t('ss', Icons.search_rounded, p.ok, 'Сохранённые поиски', 'Новые объявления по вашим фильтрам'),
        t('rev', Icons.star_outline_rounded, amber, 'Новые отзывы', 'Оценки и ответы на отзывы'),
      ]),
      _group(p, 'Тихие часы', [
        _swRow(p, Icons.bedtime_outlined, indigo, 'Не беспокоить', '${S.i.dndFrom} – ${S.i.dndTo}, без звука', S.i.dndOn,
            (v) => S.i.setDnd(on: v)),
      ]),
    ]);
  }

  Widget _innCard(Pal p) {
    final inn = (S.i.user?['inn'] ?? '').toString();
    final ok = S.i.user?['innOk'] == true && inn.length == 12;
    const k = _cGreen;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: cardDeco(p, r: 20),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: k.withOpacity(.16), borderRadius: BorderRadius.circular(11)),
          child: const Icon(Icons.verified_outlined, color: k, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ok ? 'Самозанятый · ИНН $inn' : 'Статус самозанятого (ИНН)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: p.tx)),
            Text(ok ? 'Значок «Самозанятый» отображается в вашем профиле' : 'Подтвердите 12-значный ИНН для значка доверия в профиле', style: TextStyle(color: p.mu, fontSize: 13, height: 1.3)),
          ]),
        ),
        TextButton(
          onPressed: () async {
            String msg = 'Статус обновлён';
            final r = await askFields(context, 'Проверка ИНН самозанятого', [
              FieldSpec('ИНН (12 цифр)', initial: inn, type: TextInputType.number, maxLen: 12, digitsOnly: true),
            ], ok: 'Проверить', hint: 'Проверим контрольную сумму ФНС и статус плательщика НПД.', onSubmit: (v) async {
              if (v[0].length != 12) throw Exception('ИНН должен содержать ровно 12 цифр');
              final res = await Api.call('verifyInn', {'inn': v[0]});
              await S.i.patchUser({'inn': res['inn'] ?? '', 'innOk': res['innOk'] == true});
              msg = res['msg']?.toString() ?? msg;
            });
            if (r == null || !mounted) return;
            setState(() {});
            toast(context, msg);
          },
          child: Text(ok ? 'Изменить' : 'Подтвердить', style: TextStyle(color: p.ac, fontWeight: FontWeight.w800)),
        ),
      ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
        child: Text('Проверим контрольную сумму ФНС и статус плательщика НПД.', style: TextStyle(color: p.mu, fontSize: 13, height: 1.35)),
      ),
    ]);
  }

  // Чат поддержки живёт в «Сообщениях», как в Авито: отсюда просто открываем его
  Future<void> _openSupportSheet() async {
    await _run(() async {
      final j = await Api.call('dialogs');
      final l = j['list'] is List ? j['list'] as List : const [];
      final d = l.firstWhere((e) => e is Map && e['sup'] == 1, orElse: () => null);
      if (d == null || !mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(pid: d['pid'].toString(), name: 'Поддержка ЗадаЧО', adId: 'support')));
    });
  }

  List<Widget> _dataRows(Pal p) {
    final delAt = (S.i.user?['delAt'] as num?)?.toInt() ?? 0;
    return [
        _hubRow(p, Icons.download_outlined, _cBlue, 'Скачать мои данные', 'Файл JSON: профиль, объявления, отзывы', () async {
          await _run(() async {
            final res = await Api.call('exportData');
            final jsonStr = const JsonEncoder.withIndent('  ').convert(res['data'] ?? res);
            try {
              // отдаём файлом: через «Поделиться» его можно сохранить в «Файлы» или отправить себе
              await Share.shareXFiles([XFile.fromData(Uint8List.fromList(utf8.encode(jsonStr)), mimeType: 'application/json', name: 'zadacho-data.json')],
                  fileNameOverrides: ['zadacho-data.json'], subject: 'Мои данные ЗадаЧО');
            } catch (_) {
              await Clipboard.setData(ClipboardData(text: jsonStr));
              if (mounted) toast(context, 'Не удалось создать файл, данные скопированы в буфер обмена');
            }
          });
        }),
        if (delAt > 0)
          _hubRow(p, Icons.restore_from_trash_rounded, _cGreen, 'Отменить удаление аккаунта', 'Удаление запланировано на 7 дней', () async {
            await _run(() async {
              await Api.call('cancelDelete');
              await S.i.patchUser({'delAt': 0});
              if (mounted) toast(context, 'Удаление аккаунта отменено');
            });
          })
        else
          _hubRow(p, Icons.delete_forever_outlined, p.dng, 'Удалить аккаунт', 'Отсрочка 7 дней, можно восстановить', () async {
            final r = await askFields(context, 'Удаление аккаунта', [
              const FieldSpec('Причина удаления (необязательно)'),
            ], ok: 'Запланировать удаление', hint: 'Аккаунт будет удалён через 7 дней. В течение этого срока удаление можно отменить.');
            if (r == null) return;
            await _run(() async {
              final res = await Api.call('deleteAccount', {'reason': r[0]});
              await S.i.patchUser({'delAt': res['delAt'] ?? DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch});
              if (mounted) toast(context, 'Удаление аккаунта запланировано через 7 дней');
            });
          }),
    ];
  }
}

// Раздел «Вход и пароль»: создать или сменить пароль, привязать и отвязать Яндекс ID и VK ID
class _AccountAuthCard extends StatefulWidget {
  const _AccountAuthCard();
  @override
  State<_AccountAuthCard> createState() => _AccountAuthCardState();
}

class _AccountAuthCardState extends State<_AccountAuthCard> {
  bool _loading = true, _failed = false, _busy = false;
  bool _hasPw = true;
  Set<String> _links = <String>{};
  Set<String> _avail = <String>{};

  static const _prov = [
    ['yandex', 'Яндекс ID'],
    ['vk', 'VK ID'],
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await Api.call('authInfo');
      final av = await Api.oauthProviders();
      final raw = j['links'];
      final ln = <String>{};
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) ln.add((e['provider'] ?? '').toString());
        }
      }
      if (!mounted) return;
      setState(() {
        _hasPw = j['hasPw'] != false;
        _links = ln;
        _avail = av;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _password() async {
    if (_hasPw) {
      final r = await askFields(
        context,
        'Изменить пароль',
        [
          const FieldSpec('Текущий пароль', secret: true),
          const FieldSpec('Новый пароль (от 6 символов)', secret: true, strength: true),
          const FieldSpec('Повторите новый пароль', secret: true, matchWith: 1),
        ],
        ok: 'Сохранить',
        onSubmit: (v) async {
          if (v[0].isEmpty) throw ApiError('Введите текущий пароль');
          if (v[1].length < 6) throw ApiError('Пароль должен быть не короче 6 символов');
          if (v[1] != v[2]) throw ApiError('Пароли не совпадают');
          if (v[1] == v[0]) throw ApiError('Новый пароль совпадает с текущим');
          await Api.call('chPw', {
            'old': sha256Hex('${S.i.login}:${v[0]}'),
            'hash': sha256Hex('${S.i.login}:${v[1]}'),
          });
        },
      );
      if (r != null && mounted) toast(context, 'Пароль изменён. На других устройствах вы вышли из аккаунта');
      return;
    }
    var sent = false;
    while (true) {
      final r = await askFields(
        context,
        'Создать пароль',
        [
          const FieldSpec('Новый пароль (от 6 символов)', secret: true, strength: true),
          const FieldSpec('Повторите пароль', secret: true, matchWith: 0),
        ],
        ok: 'Получить код',
        icon: Icons.lock_outline_rounded,
        step: 1,
        hint: 'Так вы сможете входить по почте или телефону. Код подтверждения придёт на',
        chip: S.i.login,
        onSubmit: (v) async {
          if (v[0].length < 6) throw ApiError('Пароль должен быть не короче 6 символов');
          if (v[0] != v[1]) throw ApiError('Пароли не совпадают');
          if (!sent) {
            await Api.call('sendCode', {'email': S.i.login, 'kind': 'pw'});
            sent = true;
          }
        },
      );
      if (r == null || !mounted) return;
      final pw = r[0];
      final c = await askFields(
        context,
        'Код из письма',
        [const FieldSpec('', otp: true, type: TextInputType.number, maxLen: 6, digitsOnly: true)],
        ok: 'Создать пароль',
        icon: Icons.mail_outline_rounded,
        step: 2,
        back: true,
        hint: 'Отправили 6 цифр на',
        chip: S.i.login,
        chipAfter: '. Он действует 10 минут.',
        resend: () => Api.call('sendCode', {'email': S.i.login, 'kind': 'pw'}),
        onSubmit: (v) async {
          if (v[0].length < 6) throw ApiError('Введите 6 цифр из письма');
          await Api.call('setPw', {'code': v[0], 'hash': sha256Hex('${S.i.login}:$pw')});
        },
      );
      if (c == null || !mounted) return;
      if (c.length == 1 && c[0] == kBackMarker) continue;
      break;
    }
    setState(() => _hasPw = true);
    toast(context, 'Пароль создан. Теперь можно входить по почте и паролю');
  }

  Future<void> _link(String k) async {
    setState(() => _busy = true);
    try {
      final j = await Api.call('oauthLinkTicket', {'provider': k});
      final tk = (j['ticket'] ?? '').toString();
      if (tk.isEmpty) throw ApiError('Не удалось начать привязку. Попробуйте ещё раз');
      await launchUrl(
        Uri.parse('https://zadacho.ru/oauth/$k/start?mode=app&link=${Uri.encodeQueryComponent(tk)}'),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (mounted) toast(context, S.i.fail(e), err: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _unlink(String k, String name) async {
    if (!_hasPw && _links.length <= 1) {
      toast(context, 'Сначала создайте пароль, иначе вы не сможете войти в аккаунт', err: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Отвязать $name?'),
        content: const Text('Входить в этот аккаунт через сервис будет нельзя.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Отвязать')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await Api.call('oauthUnlink', {'provider': k});
      if (mounted) {
        setState(() {
          _links = {..._links}..remove(k);
        });
        toast(context, '$name отвязан');
      }
    } catch (e) {
      if (mounted) toast(context, S.i.fail(e), err: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _caption(Pal p, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 0, 8),
        child: Text(t.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: .6, color: p.mu)),
      );

  Widget _provBadge(String k) {
    final ya = k == 'yandex';
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ya ? const Color(0xFFFC3F1D) : const Color(0xFF0077FF),
        shape: ya ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: ya ? null : BorderRadius.circular(11),
      ),
      child: Text(ya ? 'Я' : 'VK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: ya ? 17 : 14)),
    );
  }

  Widget _provRow(Pal p, String k, String name) {
    final on = _links.contains(k);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(children: [
        _provBadge(k),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: p.tx)),
            Text(on ? 'Привязан · вход в один клик' : 'Не привязан', style: TextStyle(color: on ? p.ok : p.mu, fontSize: 13)),
          ]),
        ),
        TextButton(
          onPressed: _busy ? null : () => on ? _unlink(k, name) : _link(k),
          child: Text(on ? 'Отвязать' : 'Привязать', style: TextStyle(color: on ? p.dng : p.ac, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: p.ac))),
      );
    }
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(children: [
          Text('Не удалось загрузить данные', style: TextStyle(color: p.mu)),
          TextButton(
            onPressed: () {
              setState(() {
                _loading = true;
                _failed = false;
              });
              _load();
            },
            child: Text('Повторить', style: TextStyle(color: p.ac, fontWeight: FontWeight.w800)),
          ),
        ]),
      );
    }
    final shown = [for (final x in _prov) if (_links.contains(x[0]) || _avail.contains(x[0])) x];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!_hasPw)
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.ac.withOpacity(.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.ac.withOpacity(.3)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, color: p.ac, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Пароль не задан', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: p.tx)),
                const SizedBox(height: 2),
                Text('Вы входите через Яндекс или VK. Создайте пароль, чтобы входить ещё и по почте или телефону.',
                    style: TextStyle(color: p.mu, fontSize: 13.5, height: 1.4)),
              ]),
            ),
          ]),
        ),
      _caption(p, 'Пароль'),
      Container(
        decoration: cardDeco(p, r: 20),
        clipBehavior: Clip.antiAlias,
        child: Tap(
          onTap: _busy ? null : () { _password(); },
          scale: .99,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: _cPurple.withOpacity(.16), borderRadius: BorderRadius.circular(11)),
                child: const Icon(Icons.lock_outline_rounded, color: _cPurple, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_hasPw ? 'Изменить пароль' : 'Создать пароль', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: p.tx)),
                  Text(_hasPw ? 'Для входа по почте или телефону' : 'Нужен для входа по почте или телефону', style: TextStyle(color: p.mu, fontSize: 13)),
                ]),
              ),
              Icon(Icons.chevron_right, color: p.mu),
            ]),
          ),
        ),
      ),
      if (shown.isNotEmpty) ...[
        _caption(p, 'Вход через сервисы'),
        Container(
          decoration: cardDeco(p, r: 20),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, indent: 64, color: p.bd),
              _provRow(p, shown[i][0], shown[i][1]),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
          child: Text('Привяжите сервис, чтобы входить в этот аккаунт без пароля. Аккаунт сервиса можно привязать только к одному профилю.',
              style: TextStyle(color: p.mu, fontSize: 12.5, height: 1.4)),
        ),
      ],
    ]);
  }
}

class _DevicesCard extends StatefulWidget {
  const _DevicesCard();
  @override
  State<_DevicesCard> createState() => _DevicesCardState();
}

class _DevicesCardState extends State<_DevicesCard> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await Api.call('devices');
      final raw = j['list'];
      if (mounted && raw is List) {
        setState(() {
          _list = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _kill({String? id, bool allOther = false}) async {
    setState(() => _busy = true);
    try {
      final j = await Api.call('killDevice', {
        if (id != null) 'id': id,
        if (allOther) 'allOther': true,
      });
      final raw = j['list'];
      if (mounted && raw is List) {
        setState(() {
          _list = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      }
      if (mounted) {
        toast(context, allOther ? 'Остальные сеансы завершены' : 'Сеанс на устройстве завершён');
      }
    } catch (e) {
      if (mounted) toast(context, S.i.fail(e), err: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final hasOthers = _list.any((d) => d['cur'] != true);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        decoration: cardDeco(p, r: 20),
        clipBehavior: Clip.antiAlias,
        child: _loading
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: p.ac))),
              )
            : Column(children: [
                if (_list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Текущее устройство активно', style: TextStyle(color: p.tx, fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                for (var i = 0; i < _list.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, indent: 64, color: p.bd),
                  _deviceRow(p, _list[i]),
                ],
              ]),
      ),
      if (hasOthers)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Container(
            decoration: cardDeco(p, r: 20),
            clipBehavior: Clip.antiAlias,
            child: Tap(
              onTap: _busy ? null : () => _kill(allOther: true),
              scale: .99,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: p.dng.withOpacity(.16), borderRadius: BorderRadius.circular(11)),
                    child: Icon(Icons.logout_rounded, color: p.dng, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text('Завершить все остальные сеансы', style: TextStyle(color: p.dng, fontWeight: FontWeight.w700, fontSize: 15.5))),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _deviceRow(Pal p, Map<String, dynamic> d) {
    final cur = d['cur'] == true;
    final dev = (d['dev'] ?? 'Устройство').toString();
    final mobile = dev.toLowerCase().contains('android') || dev.toLowerCase().contains('iphone');
    final k = cur ? p.ok : p.ac;
    var ipT = (d['ip'] ?? '').toString();
    var geoT = (d['geo'] ?? '').toString();
    if (cur && ipT.isEmpty) ipT = Api.ip;
    if (cur && geoT.isEmpty) geoT = Api.geo;
    final where = [if (ipT.isNotEmpty) ipT, if (geoT.isNotEmpty) geoT].join(' · ');
    final when = cur ? 'В сети сейчас' : 'Активность: ${ago((d['ts'] as num?)?.toInt() ?? 0)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: k.withOpacity(.16), borderRadius: BorderRadius.circular(11)),
          child: Icon(mobile ? Icons.smartphone_rounded : Icons.laptop_mac_rounded, color: k, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(dev, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.tx, fontWeight: FontWeight.w700, fontSize: 15.5)),
            Text(where.isEmpty ? 'IP и страна не определены' : where, style: TextStyle(color: p.mu, fontSize: 13)),
            Text(when, style: TextStyle(color: p.mu, fontSize: 13)),
          ]),
        ),
        if (cur)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: p.ok.withOpacity(.14), borderRadius: BorderRadius.circular(99)),
            child: Text('Это устройство', style: TextStyle(color: p.ok, fontWeight: FontWeight.w800, fontSize: 12)),
          )
        else
          TextButton(
            onPressed: _busy ? null : () => _kill(id: (d['id'] ?? '').toString()),
            child: Text('Завершить', style: TextStyle(color: p.dng, fontWeight: FontWeight.w800, fontSize: 14)),
          ),
      ]),
    );
  }
}

class ProfileEditPage extends StatelessWidget {
  const ProfileEditPage({super.key});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Изменить профиль')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: cardDeco(p, r: 20),
            child: Row(children: [
              Icon(Icons.info_outline, color: p.ac),
              const SizedBox(width: 10),
              Expanded(child: Text('Измените фото, имя, почту или номер телефона.', style: TextStyle(color: p.mu, height: 1.35))),
            ]),
          ),
          const SizedBox(height: 12),
          SettingsBody(profileOnly: true),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: const [SettingsBody()]),
    );
  }
}

class SettingsSectionPage extends StatelessWidget {
  final String section, title;
  const SettingsSectionPage({super.key, required this.section, required this.title});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [SettingsBody(section: section)]),
    );
  }
}

Future<void> confirmLogout(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Выйти из аккаунта?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Выйти')),
      ],
    ),
  );
  if (ok == true) {
    await S.i.setUser(null);
    S.i.loadAds();
  }
}

Future<void> showLeadForm(BuildContext context) async {
  final r = await askFields(
      context,
      'Для бизнеса',
      [
        FieldSpec('Имя', initial: S.i.name),
        FieldSpec('Телефон', initial: S.i.phone, type: TextInputType.phone),
        const FieldSpec('Что нужно?', multi: true),
      ],
      ok: 'Отправить',
      hint: 'Оставьте заявку, мы свяжемся с вами.');
  if (r == null || !context.mounted) return;
  if (r[1].replaceAll(RegExp(r'\D'), '').length < 8) {
    toast(context, 'Укажите телефон');
    return;
  }
  try {
    await Api.call('lead', {'name': r[0], 'phone': r[1], 'msg': r[2]});
    if (context.mounted) toast(context, 'Заявка отправлена');
  } catch (e) {
    if (context.mounted) toast(context, S.i.fail(e), err: true);
  }
}

/// Значок приложения с версией. Нажатие на него проверяет обновление.
class AppStamp extends StatefulWidget {
  const AppStamp({super.key});
  @override
  State<AppStamp> createState() => _AppStampState();
}

class _AppStampState extends State<AppStamp> {
  bool _busy = false;

  Future<void> _check() async {
    if (_busy) return;
    setState(() => _busy = true);
    await runUpdateCheck(context);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 8),
      child: Center(
        child: Tap(
          onTap: _check,
          scale: .95,
          child: AnimatedOpacity(
            opacity: _busy ? .45 : 1,
            duration: const Duration(milliseconds: 250),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Logo(size: 48),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('ЗадаЧО', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: p.tx)),
                const SizedBox(height: 2),
                Text('Версия $kAppVersion', style: TextStyle(color: p.mu, fontSize: 13)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Регион для поиска: город и радиус, с которыми по умолчанию открывается лента
class RegionPage extends StatefulWidget {
  const RegionPage({super.key});
  @override
  State<RegionPage> createState() => _RegionPageState();
}

class _RegionPageState extends State<RegionPage> {
  final _c = TextEditingController(text: S.i.regionCity);
  late String _rad = S.i.regionRad;
  late bool _first = S.i.regionFirst;
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _city(String v) {
    final had = _c.text.trim().isNotEmpty;
    setState(() {
      if (v.trim().isEmpty) {
        _rad = '';
      }
    });
  }

  Future<void> _locate() async {
    setState(() => _busy = true);
    final r = await Near.i.locate();
    String? city;
    final pos = Near.i.pos;
    if (r == NearResult.ok && pos != null) city = await Geo.reverseCity(pos.latitude, pos.longitude);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (city != null) {
        _c.text = city;
      }
    });
    if (r != NearResult.ok) {
      toast(context, nearMsg(r), err: true);
    } else if (city == null) {
      toast(context, 'Не удалось определить город', err: true);
    }
  }

  Future<void> _save() async {
    await S.i.setRegion(_c.text, '100', true);
    if (!mounted) return;
    toast(context, _c.text.trim().isEmpty ? 'Ищем по всем городам' : 'Регион для поиска: ${_c.text.trim()}');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final hasCity = _c.text.trim().isNotEmpty;

    Widget chip(String t, String v) {
      final on = _rad == v;
      return Tap(
        onTap: () {
          setState(() => _rad = v);
        },
        scale: .96,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: on ? p.ac.withOpacity(.14) : p.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: on ? p.ac : p.bd, width: on ? 1.6 : 1),
          ),
          child: Text(t, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: on ? p.ac : p.tx)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        foregroundColor: p.tx,
        elevation: 0,
        title: const Text('Регион для поиска', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Stack(children: [
        ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(16, 8, 16, 110 + MediaQuery.of(context).viewInsets.bottom),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: cardDeco(p, r: 20),
              child: CityField(
                controller: _c,
                decoration: deco(context, 'Город или регион', prefix: Icon(Icons.place_outlined, color: p.mu)),
                onChanged: _city,
              ),
            ),
            const SizedBox(height: 12),
            Tap(
              onTap: _busy ? null : _locate,
              scale: .98,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: cardDeco(p, r: 20),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: p.ac.withOpacity(.16), borderRadius: BorderRadius.circular(11)),
                    child: Icon(Icons.my_location_rounded, color: p.ac, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Определить автоматически', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: p.tx)),
                      Text('Нужен доступ к геолокации', style: TextStyle(color: p.mu, fontSize: 13)),
                    ]),
                  ),
                  if (_busy) SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.ac)) else Icon(Icons.chevron_right, color: p.mu),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
              child: Text('Лента будет открываться с этим городом. Изменить его можно и в фильтрах.', style: TextStyle(color: p.mu, fontSize: 13, height: 1.35)),
            ),
            const SizedBox(height: 14),
            if (hasCity)
              TextButton(
                onPressed: () {
                  setState(() {
                    _c.clear();
                    _rad = '';
                  });
                },
                child: Text('Искать по всем городам', style: TextStyle(color: p.ac, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(16, 22, 16, 12 + MediaQuery.of(context).viewPadding.bottom),
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [p.bg.withOpacity(0), p.bg, p.bg])),
            child: GradBtn('Сохранить', radius: 18, onTap: _save),
          ),
        ),
      ]),
    );
  }
}

// Смысловые цвета иконок: в одной категории оттенки не повторяются
const _cRed = Color(0xFFFF5A4F), _cOrange = Color(0xFFFF6B3D), _cAmber = Color(0xFFF5B301), _cGreen = Color(0xFF2EC27E);
const _cCyan = Color(0xFF1FB6D4), _cBlue = Color(0xFF4C8DFF), _cPurple = Color(0xFFA678FF);

/// Шторка «Где вы ищете?» после первого входа (как на сайте): город, определение по геолокации, «Пропустить»
Future<void> showRegionSheet(BuildContext context) {
  final p = pal(context);
  final surface = p.card; // нейтральный фон, без оранжевого оттенка
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(.6),
    builder: (c) => Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: p.bd),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
          child: const SingleChildScrollView(child: _RegionSheetBody()),
        ),
      ),
    ),
  );
}

class _RegionSheetBody extends StatefulWidget {
  const _RegionSheetBody();
  @override
  State<_RegionSheetBody> createState() => _RegionSheetBodyState();
}

class _RegionSheetBodyState extends State<_RegionSheetBody> {
  final _c = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() => _busy = true);
    final r = await Near.i.locate();
    String? city;
    final pos = Near.i.pos;
    if (r == NearResult.ok && pos != null) city = await Geo.reverseCity(pos.latitude, pos.longitude);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (city != null) _c.text = city;
    });
    if (r != NearResult.ok) {
      toast(context, nearMsg(r), err: true);
    } else if (city == null) {
      toast(context, 'Не удалось определить город', err: true);
    }
  }

  Future<void> _go(bool skip) async {
    final nav = Navigator.of(context);
    await S.i.setRegion(skip ? '' : _c.text, '100', true);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final has = _c.text.trim().isNotEmpty;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: p.mu.withOpacity(.45), borderRadius: BorderRadius.circular(99)))),
        const SizedBox(height: 18),
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [p.ac, p.ac2]),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.place_rounded, color: Colors.white, size: 27),
        ),
        const SizedBox(height: 14),
        Text('Где вы ищете?', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: p.tx, letterSpacing: -.5)),
        const SizedBox(height: 6),
        Text('Покажем подработки и услуги рядом с вами. Город можно сменить в любой момент в настройках.',
            style: TextStyle(color: p.mu, fontSize: 15, height: 1.4)),
        const SizedBox(height: 18),
        CityField(
          controller: _c,
          decoration: deco(context, 'Город или регион', prefix: Icon(Icons.place_outlined, color: p.mu)),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Tap(
          onTap: _busy ? null : _locate,
          scale: .98,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: dark ? const Color(0xFF16120F) : p.bg2, borderRadius: BorderRadius.circular(20), border: Border.all(color: p.bd)),
            child: Row(children: [
              // как значки в «Что ищете?»: нейтральная плитка и оранжевая иконка
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: dark ? const Color(0xFF2A2521) : p.card, borderRadius: BorderRadius.circular(16)),
                child: Icon(Icons.my_location_rounded, color: p.ac, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Определить автоматически', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.tx)),
                  const SizedBox(height: 3),
                  Text('Нужен доступ к геолокации', style: TextStyle(fontSize: 13.5, height: 1.3, color: p.mu)),
                ]),
              ),
              if (_busy) SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.ac)),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        GradBtn('Продолжить', radius: 16, onTap: has ? () => _go(false) : null),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => _go(true),
            child: Text('Пропустить, искать везде', style: TextStyle(color: p.mu, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}
