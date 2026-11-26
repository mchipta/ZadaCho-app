import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'ad_page.dart';
import 'api.dart';
import 'info.dart';
import 'legal.dart';
import 'models.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

// Группы полей на вкладке «Тексты» (те же, что в админке сайта)
class _SG {
  final String title;
  final List<String> keys;
  const _SG(this.title, this.keys);
}

const _siteGroups = <_SG>[
  _SG('Главная', ['h1a', 'h1b', 'lead']),
  _SG('Блоки на главной', ['stats', 'faq']),
  _SG('Страницы', ['year', 'about', 'biz']),
  _SG('Контакты и подвал', ['phone', 'email', 'addr', 'hours', 'social', 'tg', 'vk', 'foot', 'copy']),
];

const _siteLabels = <String, String>{
  'h1a': 'Заголовок: первая строка',
  'h1b': 'Заголовок: цветная строка',
  'lead': 'Подзаголовок',
  'stats': 'Цифры: по строке «число|подпись»',
  'faq': 'Вопросы: по строке «Вопрос|Ответ»',
  'year': 'Год основания',
  'about': 'Страница «О нас» (абзацы через пустую строку)',
  'biz': 'Страница «Для бизнеса»',
  'phone': 'Телефон',
  'email': 'Почта',
  'addr': 'Адрес',
  'hours': 'Часы работы',
  'social': 'Ник по умолчанию (например @name)',
  'tg': 'Telegram: ник без @ (если отличается)',
  'vk': 'VK: ник без @ (если отличается)',
  'foot': 'Описание в подвале',
  'copy': 'Строка внизу',
};

const _siteMulti = <String>{'lead', 'stats', 'faq', 'about', 'biz', 'foot', 'copy'};

// Закреплённая полоса разделов под плитками (на телефоне)
class _PinDelegate extends SliverPersistentHeaderDelegate {
  final double h;
  final Widget child;
  _PinDelegate(this.h, this.child);
  @override
  double get minExtent => h;
  @override
  double get maxExtent => h;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;
  @override
  bool shouldRebuild(covariant _PinDelegate oldDelegate) => true;
}

class _AdminPageState extends State<AdminPage> {
  static const _tabs = ['usr', 'mod', 'rep', 'push', 'leads', 'site', 'legal'];
  static const _tabNames = ['Пользователи', 'Объявления', 'Жалобы', 'Push-рассылка', 'Заявки', 'Тексты', 'Документы'];
  static const _tabSubs = [
    'Все зарегистрированные аккаунты',
    'Модерация и статусы объявлений',
    'Жалобы пользователей',
    'Уведомления в приложении и на сайте',
    'Заявки от бизнеса',
    'Главная, страницы, контакты и подвал',
    'Оферта, политика конфиденциальности, согласие',
  ];
  static const _tabIcons = [
    Icons.people_alt_rounded,
    Icons.inventory_2_rounded,
    Icons.flag_rounded,
    Icons.campaign_rounded,
    Icons.mail_rounded,
    Icons.edit_note_rounded,
    Icons.description_rounded,
  ];

  String tab = 'mod';
  String _af = 'all'; // фильтр объявлений: all / open / hidden / closed
  Map<String, dynamic>? d;
  bool loading = true;
  String? err;
  bool _saving = false;
  List<int?> _cnt = const [];

  final _sc = ScrollController();
  final _kpiKey = GlobalKey();
  final List<GlobalKey> _pillKeys = List<GlobalKey>.generate(7, (_) => GlobalKey());

  final _pushTitle = TextEditingController(text: 'ЗадаЧО');
  final _pushBody = TextEditingController();
  final _pushTo = TextEditingController();
  bool _sendingPush = false;

  final _uq = TextEditingController();

  bool _siteLoaded = false, _legalLoaded = false;
  final Map<String, TextEditingController> _siteC = {
    for (final g in _siteGroups)
      for (final k in g.keys) k: TextEditingController(),
  };
  final Map<String, TextEditingController> _legalC = {
    for (final k in kLegalTitles.keys) k: TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sc.dispose();
    _pushTitle.dispose();
    _pushBody.dispose();
    _pushTo.dispose();
    _uq.dispose();
    for (final c in _siteC.values) {
      c.dispose();
    }
    for (final c in _legalC.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final j = await Api.call('adm');
      if (mounted) {
        setState(() {
          d = j;
          err = null;
        });
      }
    } catch (e) {
      final m = S.i.fail(e);
      if (mounted) setState(() => err = m);
    }
    if (mounted) setState(() => loading = false);
  }

  List<Map<String, dynamic>> _l(String k) {
    final v = d == null ? null : d![k];
    if (v is! List) return [];
    return v.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  int _len(String k) {
    final v = d == null ? null : d![k];
    return v is List ? v.length : 0;
  }

  Future<void> _do(String a, Map<String, dynamic> data, String okMsg) async {
    try {
      await Api.call(a, data);
      if (mounted) toast(context, okMsg);
      S.i.loadAds();
      await _load();
    } catch (e) {
      if (mounted) toast(context, S.i.fail(e), err: true);
    }
  }

  Future<void> _sendPushBroadcast() async {
    final body = _pushBody.text.trim();
    if (body.isEmpty) {
      toast(context, 'Введите текст Push-уведомления');
      return;
    }
    setState(() => _sendingPush = true);
    try {
      await Api.call('sendPush', {
        'title': _pushTitle.text.trim().isEmpty ? 'ЗадаЧО' : _pushTitle.text.trim(),
        'body': body,
        'target': _pushTo.text.trim().isEmpty ? 'all' : _pushTo.text.trim(),
        'to': _pushTo.text.trim(),
      });
      _pushBody.clear();
      if (mounted) toast(context, 'Push-уведомление разослано!');
      await _load();
      S.i.refreshUnread();
    } catch (e) {
      if (mounted) toast(context, S.i.fail(e), err: true);
    }
    if (mounted) setState(() => _sendingPush = false);
  }

  Future<bool> _confirm(String text) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Да')),
        ],
      ),
    );
    return r == true;
  }

  // ---------- тексты сайта и документы ----------

  Future<void> _loadSite() async {
    if (_siteLoaded) return;
    try {
      final m = await loadSite();
      for (final e in _siteC.entries) {
        e.value.text = m[e.key] ?? '';
      }
      _siteLoaded = true;
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) toast(context, S.i.fail(e), err: true);
    }
  }

  Future<void> _loadLegal() async {
    if (_legalLoaded) return;
    try {
      final m = await loadLegal(force: true);
      for (final e in _legalC.entries) {
        e.value.text = m[e.key] ?? '';
      }
      _legalLoaded = true;
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) toast(context, S.i.fail(e), err: true);
    }
  }

  Future<void> _saveSite() async {
    final o = <String, String>{for (final e in _siteC.entries) e.key: e.value.text};
    setState(() => _saving = true);
    try {
      await Api.call('saveSite', {'site': jsonEncode(o)});
      if (mounted) toast(context, 'Тексты сохранены, сайт обновлён');
    } catch (e) {
      if (mounted) toast(context, S.i.fail(e), err: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _resetSite() async {
    if (!await _confirm('Вернуть исходные тексты сайта?')) return;
    try {
      await Api.call('saveSite', {'site': ''});
      _siteLoaded = false;
      await _loadSite();
      if (mounted) toast(context, 'Тексты сброшены');
    } catch (e) {
      if (mounted) toast(context, S.i.fail(e), err: true);
    }
  }

  Future<void> _saveLegal() async {
    final o = <String, String>{for (final e in _legalC.entries) e.key: e.value.text};
    final js = jsonEncode(o);
    if (js.length > 47000) {
      toast(context, 'Слишком длинные тексты: сократите документы');
      return;
    }
    setState(() => _saving = true);
    try {
      await Api.call('saveLegal', {'legal': js});
      await loadLegal(force: true);
      if (mounted) toast(context, 'Документы сохранены');
    } catch (e) {
      if (mounted) toast(context, S.i.fail(e), err: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _resetLegal() async {
    if (!await _confirm('Вернуть исходные документы?')) return;
    try {
      await Api.call('saveLegal', {'legal': ''});
      _legalLoaded = false;
      await _loadLegal();
      if (mounted) toast(context, 'Документы сброшены');
    } catch (e) {
      if (mounted) toast(context, S.i.fail(e), err: true);
    }
  }

  Future<void> _delUser(String login) async {
    if (login.isEmpty) return;
    if (await _confirm('Удалить аккаунт $login навсегда?')) {
      await _do('delUser', {'login': login}, 'Аккаунт удалён');
    }
  }

  // ---------- навигация по разделам ----------

  void _go(String t) {
    setState(() => tab = t);
    if (t == 'site') _loadSite();
    if (t == 'legal') _loadLegal();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final i = _tabs.indexOf(t);
      if (i >= 0) {
        final c = _pillKeys[i].currentContext;
        if (c != null) {
          Scrollable.ensureVisible(c, alignment: .5, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      }
      // если пролистали далеко вниз — возвращаем к началу раздела (под плитками)
      final ro = _kpiKey.currentContext?.findRenderObject();
      if (_sc.hasClients && ro is RenderBox) {
        final h = ro.size.height;
        if (_sc.offset > h) _sc.jumpTo(h);
      }
    });
  }

  // ---------- мелкие детали оформления ----------

  String _ini(String s) {
    final t = s.trim();
    return t.isEmpty ? '?' : String.fromCharCode(t.runes.first).toUpperCase();
  }

  Widget _av(Pal p, String name, {double size = 44}) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: p.ac.withOpacity(.14)),
        child: Text(_ini(name), style: TextStyle(color: p.ac, fontWeight: FontWeight.w800, fontSize: size * .42)),
      );

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: c.withOpacity(.14),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: c.withOpacity(.35)),
        ),
        child: Text(t, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
      );

  Widget _card(Pal p, Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: cardDeco(p, r: 18),
        child: child,
      );

  Widget _ii(Pal p, IconData ic, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ic, size: 15, color: p.mu),
        const SizedBox(width: 6),
        Flexible(child: Text(t, style: TextStyle(color: p.mu, fontSize: 13.5))),
      ]);

  Widget _quote(Pal p, String label, String text, Color bar) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: TextStyle(color: p.mu, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .4)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(width: 3, color: bar),
                Expanded(
                  child: Container(
                    color: p.bg2,
                    padding: const EdgeInsets.all(10),
                    child: Text(text, style: TextStyle(color: p.tx, height: 1.35)),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      );

  // кнопка действия: tone 0 — обычная, 1 — опасная (красная), 2 — «хорошая» (зелёная)
  Widget _ab(Pal p, String t, IconData ic, VoidCallback f, {int tone = 0}) {
    final col = tone == 1 ? p.dng : (tone == 2 ? p.ok : p.tx);
    return Tap(
      onTap: f,
      scale: .96,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: tone == 0 ? p.bg2 : col.withOpacity(.09),
          borderRadius: BorderRadius.circular(R.s),
          border: Border.all(color: tone == 0 ? p.bd : col.withOpacity(.3)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(ic, size: 17, color: col),
          const SizedBox(width: 7),
          Flexible(
            child: Text(t, textAlign: TextAlign.center, style: TextStyle(color: col, fontWeight: FontWeight.w700, fontSize: 14, height: 1.2)),
          ),
        ]),
      ),
    );
  }

  // кнопки по две в ряд; последняя нечётная — на всю ширину
  Widget _acts(List<Widget> bs) {
    final rows = <Widget>[];
    for (var i = 0; i < bs.length; i += 2) {
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: bs[i]),
            if (i + 1 < bs.length) ...[const SizedBox(width: 8), Expanded(child: bs[i + 1])],
          ]),
        ),
      ));
    }
    return Column(children: rows);
  }

  Widget _empty(Pal p, String t) => Padding(
        padding: const EdgeInsets.all(32),
        child: Text(t, textAlign: TextAlign.center, style: TextStyle(color: p.mu)),
      );

  // ---------- плитки, меню разделов ----------

  Widget _kpi(Pal p, IconData ic, Color col, String v, String label, VoidCallback f) => Tap(
        onTap: f,
        scale: .97,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: cardDeco(p, r: 18),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: col.withOpacity(.15), borderRadius: BorderRadius.circular(13)),
              child: Icon(ic, color: col, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: p.tx, height: 1.1)),
                const SizedBox(height: 2),
                Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.mu, height: 1.2)),
              ]),
            ),
          ]),
        ),
      );

  Widget _kpis(Pal p, bool wide) {
    final open = _l('ads').where((m) => (m['status'] ?? '').toString() == 'open').length;
    final t1 = _kpi(p, Icons.people_alt_rounded, p.ac, '${d!['users'] ?? 0}', 'пользователей', () => _go('usr'));
    final t2 = _kpi(p, Icons.inventory_2_rounded, p.ok, '$open', 'активных объявлений', () {
      setState(() => _af = 'open');
      _go('mod');
    });
    final t3 = _kpi(p, Icons.flag_rounded, p.dng, '${_len('reports')}', 'жалоб', () => _go('rep'));
    final t4 = _kpi(p, Icons.mail_rounded, p.ac2, '${_len('leads')}', 'заявок', () => _go('leads'));
    if (wide) {
      return Row(children: [
        Expanded(child: t1),
        const SizedBox(width: 12),
        Expanded(child: t2),
        const SizedBox(width: 12),
        Expanded(child: t3),
        const SizedBox(width: 12),
        Expanded(child: t4),
      ]);
    }
    return Column(children: [
      Row(children: [Expanded(child: t1), const SizedBox(width: 10), Expanded(child: t2)]),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: t3), const SizedBox(width: 10), Expanded(child: t4)]),
    ]);
  }

  Widget _badge(Pal p, int n, bool on) => Container(
        height: 20,
        constraints: const BoxConstraints(minWidth: 22),
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? Colors.white.withOpacity(.26) : p.bg2,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? Colors.white : p.tx)),
      );

  // «таблетка» раздела (телефон)
  Widget _pill(Pal p, int i) {
    final on = tab == _tabs[i];
    final n = i < _cnt.length ? _cnt[i] : null;
    return Padding(
      key: _pillKeys[i],
      padding: const EdgeInsets.only(right: 8),
      child: Tap(
        onTap: () => _go(_tabs[i]),
        scale: .95,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            gradient: on ? LinearGradient(colors: [p.ac, p.ac2]) : null,
            color: on ? null : p.card,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: on ? Colors.transparent : p.bd),
            boxShadow: on ? [BoxShadow(color: p.ac.withOpacity(.25), blurRadius: 12, offset: const Offset(0, 4))] : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_tabIcons[i], size: 18, color: on ? Colors.white : p.mu),
            const SizedBox(width: 8),
            Text(_tabNames[i], style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: on ? Colors.white : p.mu)),
            if (n != null) ...[const SizedBox(width: 8), _badge(p, n, on)],
          ]),
        ),
      ),
    );
  }

  Widget _navPills(Pal p) => Container(
        decoration: BoxDecoration(color: p.bg, border: Border(bottom: BorderSide(color: p.bd))),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 9, 8, 9),
          child: Row(children: [for (var i = 0; i < _tabs.length; i++) _pill(p, i)]),
        ),
      );

  // боковое меню (широкий экран)
  Widget _sidebar(Pal p) {
    Widget item(int i) {
      final on = tab == _tabs[i];
      final n = i < _cnt.length ? _cnt[i] : null;
      return Tap(
        onTap: () => _go(_tabs[i]),
        scale: .98,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: on ? LinearGradient(colors: [p.ac, p.ac2]) : null,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Icon(_tabIcons[i], size: 20, color: on ? Colors.white : p.mu),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_tabNames[i], style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: on ? Colors.white : p.mu)),
            ),
            if (n != null) _badge(p, n, on),
          ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: cardDeco(p, r: R.l),
      child: Column(children: [
        for (var i = 0; i < 5; i++) item(i),
        Divider(color: p.bd, height: 14),
        item(5),
        item(6),
      ]),
    );
  }

  Widget _titleBlock(Pal p) {
    final i = _tabs.indexOf(tab);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_tabNames[i], style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.tx)),
        const SizedBox(height: 2),
        Text(_tabSubs[i], style: TextStyle(fontSize: 14, color: p.mu)),
      ]),
    );
  }

  // ---------- раздел «Объявления» ----------

  Widget _pillBtn(Pal p, String label, int n, bool on, VoidCallback f) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Tap(
          onTap: f,
          scale: .95,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: on ? p.tx : p.card,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: on ? p.tx : p.bd),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: on ? p.bg : p.mu)),
              const SizedBox(width: 7),
              Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: (on ? p.bg : p.mu).withOpacity(.7))),
            ]),
          ),
        ),
      );

  Widget _adsHead(Pal p) {
    final all = _l('ads');
    int n(String s) => s == 'all' ? all.length : all.where((m) => (m['status'] ?? '').toString() == s).length;
    const opts = [
      ['all', 'Все'],
      ['open', 'Активные'],
      ['hidden', 'Скрытые'],
      ['closed', 'Снятые'],
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final o in opts) _pillBtn(p, o[1], n(o[0]), _af == o[0], () => setState(() => _af = o[0])),
        ]),
      ),
    );
  }

  List<Widget> _adCards(Pal p) {
    final list = _l('ads').where((m) => _af == 'all' || (m['status'] ?? '').toString() == _af).toList();
    list.sort((a, b) => ((b['ts'] as num?) ?? 0).toInt().compareTo(((a['ts'] as num?) ?? 0).toInt()));
    if (list.isEmpty) return [_empty(p, 'Объявлений в этом разделе нет')];
    return [for (final m in list) _adCard(p, m)];
  }

  Widget _adCard(Pal p, Map<String, dynamic> m) {
    final ad = Ad.fromJson(m);
    final login = (m['login'] ?? '').toString();
    final hidden = ad.status == 'hidden';
    final sc = ad.status == 'open' ? p.ok : (hidden ? p.dng : p.mu);
    final sl = ad.status == 'open' ? 'активно' : (hidden ? 'скрыто' : (ad.status == 'closed' ? 'снято' : ad.status));
    return AdCard(
      ad: ad,
      showFav: false,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdPage(ad: ad))),
      footer: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _chip(sl, sc),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${ad.author}${login.isEmpty ? '' : ' ($login)'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.mu, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        _acts([
          _ab(p, hidden ? 'Показать' : 'Скрыть', hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
              () => _do('mod', {'id': ad.id, 's': hidden ? 'open' : 'hidden'}, hidden ? 'Объявление показано' : 'Объявление скрыто'),
              tone: hidden ? 2 : 0),
          if (login.isNotEmpty)
            _ab(p, ad.ver ? 'Снять проверку' : 'Проверить автора', Icons.verified_rounded,
                () => _do('verify', {'login': login, 'on': !ad.ver}, ad.ver ? 'Проверка снята' : 'Автор проверен'),
                tone: ad.ver ? 1 : 2),
          if (login.isNotEmpty)
            _ab(p, 'Бан автора', Icons.block_rounded, () async {
              if (await _confirm('Заблокировать аккаунт $login и скрыть его объявления?')) {
                await _do('ban', {'login': login, 'ban': true, 'on': true}, 'Пользователь заблокирован');
              }
            }, tone: 1),
          _ab(p, 'Удалить', Icons.delete_outline_rounded, () async {
            if (await _confirm('Удалить объявление «${ad.title}»?')) {
              await _do('mod', {'id': ad.id, 's': 'deleted'}, 'Объявление удалено');
            }
          }, tone: 1),
        ]),
      ]),
    );
  }

  // ---------- раздел «Пользователи» ----------

  Widget _usersHead(Pal p) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          contextMenuBuilder: appContextMenu,
          controller: _uq,
          style: TextStyle(color: p.tx),
          onChanged: (_) => setState(() {}),
          decoration: deco(context, null, hint: 'Поиск: почта, имя или телефон', prefix: Icon(Icons.search_rounded, color: p.mu)),
        ),
      );

  List<Widget> _userCards(Pal p) {
    final q = _uq.text.trim().toLowerCase();
    final qd = q.replaceAll(RegExp(r'\D'), '');
    final list = _l('userList').where((u) {
      if (q.isEmpty) return true;
      final login = (u['login'] ?? '').toString().toLowerCase();
      final name = (u['name'] ?? '').toString().toLowerCase();
      final ph = (u['phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      return login.contains(q) || name.contains(q) || (qd.isNotEmpty && ph.contains(qd));
    }).toList();
    if (list.isEmpty) return [_empty(p, 'Никого не найдено')];
    return [
      for (final u in list)
        () {
          final login = (u['login'] ?? '').toString();
          final name = (u['name'] ?? '').toString();
          final phone = (u['phone'] ?? '').toString();
          final created = ((u['created'] as num?) ?? 0).toInt();
          final shown = name.isEmpty ? login : name;
          return _card(
            p,
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _av(p, shown),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(shown, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: p.tx)),
                    if (name.isNotEmpty) Text(login, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.mu, fontSize: 13.5)),
                  ]),
                ),
                Wrap(spacing: 6, children: [
                  if (u['banned'] == true) _chip('бан', p.dng),
                  if (u['ver'] == true) _chip('проверен', p.ok),
                ]),
              ]),
              if (phone.isNotEmpty || created > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(spacing: 16, runSpacing: 4, children: [
                    if (phone.isNotEmpty) _ii(p, Icons.phone_rounded, phone),
                    if (created > 0) _ii(p, Icons.calendar_today_rounded, ago(created)),
                  ]),
                ),
              const SizedBox(height: 12),
              _acts([_ab(p, 'Удалить навсегда', Icons.delete_outline_rounded, () => _delUser(login), tone: 1)]),
            ]),
          );
        }(),
    ];
  }

  // ---------- раздел «Жалобы» ----------

  List<Widget> _reportCards(Pal p) {
    final ads = _l('ads');
    final reports = _l('reports');
    if (reports.isEmpty) return [_empty(p, 'Жалоб нет')];
    return [for (final r in reports) _report(p, r, ads)];
  }

  Widget _report(Pal p, Map<String, dynamic> r, List<Map<String, dynamic>> ads) {
    final rawId = (r['adId'] ?? '').toString();
    final isUserRep = rawId.startsWith('user:');
    final targetPid = isUserRep ? rawId.substring(5) : '';
    Map<String, dynamic>? am;
    if (!isUserRep) {
      for (final a in ads) {
        if (a['id'].toString() == rawId) am = a;
      }
    }
    final title = isUserRep
        ? 'Жалоба на пользователя ($targetPid)'
        : am == null
            ? 'Объявление удалено ($rawId)'
            : (am['title'] ?? '').toString();
    final ad = am == null ? null : Ad.fromJson(am);
    final hidden = ad != null && ad.status == 'hidden';
    return _card(
      p,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: p.tx, height: 1.3))),
          if (ad != null) ...[
            const SizedBox(width: 8),
            _chip(ad.status == 'open' ? 'активно' : (hidden ? 'скрыто' : 'снято'), ad.status == 'open' ? p.ok : (hidden ? p.dng : p.mu)),
          ],
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 16, runSpacing: 4, children: [
          if (ad != null) _ii(p, Icons.person_rounded, ad.author),
          _ii(p, Icons.flag_rounded, 'от ${(r['login'] ?? '').toString()}'),
          _ii(p, Icons.schedule_rounded, ago(((r['ts'] as num?) ?? 0).toInt())),
        ]),
        _quote(p, 'Причина жалобы', (r['reason'] ?? '').toString(), p.dng),
        const SizedBox(height: 12),
        _acts([
          if (ad != null) ...[
            _ab(p, 'Открыть', Icons.open_in_new_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdPage(ad: ad)))),
            if (!hidden) _ab(p, 'Скрыть', Icons.visibility_off_rounded, () => _do('mod', {'id': ad.id, 's': 'hidden'}, 'Объявление скрыто')),
            if (ad.pid.isNotEmpty)
              _ab(p, 'Заблокировать автора', Icons.block_rounded, () async {
                if (await _confirm('Заблокировать автора объявления «${ad.author}»?')) {
                  await _do('ban', {'pid': ad.pid, 'on': true}, 'Автор заблокирован');
                }
              }, tone: 1),
            _ab(p, 'Удалить', Icons.delete_outline_rounded, () async {
              if (await _confirm('Удалить объявление «${ad.title}»?')) {
                await _do('mod', {'id': ad.id, 's': 'deleted'}, 'Объявление удалено');
              }
            }, tone: 1),
          ],
          if (isUserRep && targetPid.isNotEmpty)
            _ab(p, 'Заблокировать пользователя', Icons.block_rounded, () async {
              if (await _confirm('Заблокировать пользователя $targetPid?')) {
                await _do('ban', {'pid': targetPid, 'on': true}, 'Пользователь заблокирован');
              }
            }, tone: 1),
        ]),
      ]),
    );
  }

  // ---------- раздел «Заявки» ----------

  List<Widget> _leadCards(Pal p) {
    final leads = _l('leads');
    if (leads.isEmpty) return [_empty(p, 'Заявок нет')];
    return [for (final r in leads) _lead(p, r)];
  }

  Widget _lead(Pal p, Map<String, dynamic> r) {
    final ph = (r['phone'] ?? '').toString();
    final name = (r['name'] ?? '').toString();
    final msg = (r['msg'] ?? '').toString();
    return _card(
      p,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _av(p, name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: p.tx)),
              const SizedBox(height: 2),
              _ii(p, Icons.schedule_rounded, ago(((r['ts'] as num?) ?? 0).toInt())),
            ]),
          ),
        ]),
        if (msg.isNotEmpty) _quote(p, 'Сообщение', msg, p.ac),
        if (ph.isNotEmpty) ...[
          const SizedBox(height: 12),
          _acts([_ab(p, ph, Icons.phone_rounded, () => launchUrl(Uri(scheme: 'tel', path: ph.replaceAll(RegExp(r'[^\d+]'), ''))), tone: 2)]),
        ],
      ]),
    );
  }

  // ---------- раздел «Push-рассылка» ----------

  Widget _pushForm(Pal p) => _card(
        p,
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: p.ac.withOpacity(.15), borderRadius: BorderRadius.circular(13)),
              child: Icon(Icons.campaign_rounded, color: p.ac, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Отправить Push-уведомление', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: p.tx)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            'Уведомление придёт в системную шторку Android-приложения и всплывёт на сайте у всех пользователей (или у конкретного человека).',
            style: TextStyle(color: p.mu, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            contextMenuBuilder: appContextMenu,
            controller: _pushTitle,
            style: TextStyle(color: p.tx),
            decoration: deco(context, 'Заголовок', hint: 'ЗадаЧО'),
          ),
          const SizedBox(height: 10),
          TextField(
            contextMenuBuilder: appContextMenu,
            controller: _pushBody,
            minLines: 2,
            maxLines: 4,
            maxLength: 300,
            style: TextStyle(color: p.tx),
            decoration: deco(context, 'Текст Push-уведомления', hint: 'Например: Новые подработки в вашем городе!'),
          ),
          const SizedBox(height: 4),
          TextField(
            contextMenuBuilder: appContextMenu,
            controller: _pushTo,
            style: TextStyle(color: p.tx),
            decoration: deco(context, 'Кому (оставьте пустым — ВСЕМ)', hint: 'Пусто = всем, либо email / pid'),
          ),
          const SizedBox(height: 12),
          GradBtn('Разослать Push-уведомление', icon: Icons.send_rounded, busy: _sendingPush, onTap: _sendPushBroadcast),
        ]),
      );

  List<Widget> _pushHist(Pal p) {
    final pushes = _l('pushes');
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
        child: Text('История Push-рассылок (${pushes.length})', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: p.tx)),
      ),
      if (pushes.isEmpty) _empty(p, 'Рассылок пока не было'),
      for (final item in pushes)
        _card(
          p,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text((item['title'] ?? 'ЗадаЧО').toString(), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: p.tx)),
              ),
              const SizedBox(width: 8),
              _chip(
                ((item['target'] ?? item['to'] ?? '').toString().isEmpty || (item['target'] ?? item['to']) == 'all')
                    ? 'Всем'
                    : 'Адресно: ${item['target'] ?? item['to']}',
                p.ok,
              ),
            ]),
            const SizedBox(height: 4),
            _ii(p, Icons.schedule_rounded, ago(((item['ts'] as num?) ?? 0).toInt())),
            _quote(p, 'Текст', (item['body'] ?? '').toString(), p.ac),
            const SizedBox(height: 12),
            _acts([_ab(p, 'Удалить', Icons.delete_outline_rounded, () => _do('delPush', {'id': item['id']}, 'Push удалён'), tone: 1)]),
          ]),
        ),
    ];
  }

  // ---------- разделы «Тексты» и «Документы» ----------

  Widget _acc(Pal p, String title, bool open, List<Widget> kids) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: cardDeco(p, r: 18),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: ValueKey('$tab-$title'),
            initiallyExpanded: open,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            shape: const Border(),
            collapsedShape: const Border(),
            iconColor: p.mu,
            collapsedIconColor: p.mu,
            title: Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: p.tx)),
            children: kids,
          ),
        ),
      );

  Widget _tf(Pal p, TextEditingController c, String label, {int lines = 1, int maxLines = 1}) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextField(
          contextMenuBuilder: appContextMenu,
          controller: c,
          minLines: lines,
          maxLines: maxLines,
          style: TextStyle(color: p.tx, height: 1.35),
          decoration: deco(context, label),
        ),
      );

  List<Widget> _siteForm(Pal p, bool wide) {
    if (!_siteLoaded) return [Padding(padding: const EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: p.ac)))];
    return [
      for (var gi = 0; gi < _siteGroups.length; gi++)
        _acc(p, _siteGroups[gi].title, wide || gi == 0, [
          for (final k in _siteGroups[gi].keys)
            _tf(p, _siteC[k]!, _siteLabels[k] ?? k,
                lines: _siteMulti.contains(k) ? 3 : 1, maxLines: _siteMulti.contains(k) ? 12 : 1),
        ]),
    ];
  }

  List<Widget> _legalForm(Pal p, bool wide) {
    if (!_legalLoaded) return [Padding(padding: const EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: p.ac)))];
    return [
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.bg2, borderRadius: BorderRadius.circular(R.m), border: Border.all(color: p.bd)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.description_rounded, size: 18, color: p.ac),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Оферта, политика конфиденциальности и согласие на обработку данных. Они показываются на сайте и в приложении. Заголовок раздела — строка, начинающаяся с «## », абзацы разделяются пустой строкой. Места в [КВАДРАТНЫХ СКОБКАХ] замените на данные вашей организации или ИП.',
              style: TextStyle(color: p.mu, fontSize: 13.5, height: 1.4),
            ),
          ),
        ]),
      ),
      for (final k in kLegalTitles.keys) _acc(p, kLegalTitles[k] ?? k, wide, [_tf(p, _legalC[k]!, 'Текст документа', lines: 10, maxLines: 16)]),
    ];
  }

  // компактная панель сохранения: две кнопки в один ряд
  Widget _barBtn(Pal p, String t, bool primary, VoidCallback f) => Tap(
        onTap: _saving ? null : f,
        scale: .96,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            gradient: primary ? LinearGradient(colors: [p.ac, p.ac2]) : null,
            color: primary ? null : p.card,
            borderRadius: BorderRadius.circular(14),
            border: primary ? null : Border.all(color: p.bd),
          ),
          child: primary && _saving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(t, maxLines: 1, style: TextStyle(color: primary ? Colors.white : p.tx, fontWeight: FontWeight.w800, fontSize: 14.5)),
                ),
        ),
      );

  Widget _saveBar(Pal p) {
    final site = tab == 'site';
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        padding: const EdgeInsets.all(8),
        decoration: cardDeco(p, r: 20),
        child: Row(children: [
          Expanded(flex: 13, child: _barBtn(p, site ? 'Сохранить тексты' : 'Сохранить документы', true, site ? _saveSite : _saveLegal)),
          const SizedBox(width: 8),
          Expanded(flex: 10, child: _barBtn(p, 'Вернуть исходные', false, site ? _resetSite : _resetLegal)),
        ]),
      ),
    );
  }

  // ---------- сборка экрана ----------

  List<Widget> _items(Pal p, bool wide) {
    if (tab == 'push') {
      if (wide) {
        return [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _pushForm(p)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _pushHist(p))),
          ]),
        ];
      }
      return [_pushForm(p), ..._pushHist(p)];
    }
    if (tab == 'site') return _siteForm(p, wide);
    if (tab == 'legal') return _legalForm(p, wide);
    final head = tab == 'usr' ? _usersHead(p) : (tab == 'mod' ? _adsHead(p) : null);
    final cards = tab == 'usr' ? _userCards(p) : (tab == 'mod' ? _adCards(p) : (tab == 'rep' ? _reportCards(p) : _leadCards(p)));
    if (wide) {
      return [
        if (head != null) head,
        LayoutBuilder(builder: (c, bc) {
          final w = (bc.maxWidth - 12) / 2;
          return Wrap(spacing: 12, children: [for (final x in cards) SizedBox(width: w, child: x)]);
        }),
      ];
    }
    return [if (head != null) head, ...cards];
  }

  Widget _narrow(Pal p) => RefreshIndicator(
        color: p.ac,
        onRefresh: _load,
        child: CustomScrollView(
          controller: _sc,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: Padding(key: _kpiKey, padding: const EdgeInsets.fromLTRB(16, 4, 16, 14), child: _kpis(p, false))),
            SliverPersistentHeader(pinned: true, delegate: _PinDelegate(58, _navPills(p))),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              sliver: SliverList(delegate: SliverChildListDelegate(_items(p, false))),
            ),
          ],
        ),
      );

  Widget _wide(Pal p) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 248,
          child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 4, 8, 24), child: _sidebar(p)),
        ),
        Expanded(
          child: RefreshIndicator(
            color: p.ac,
            onRefresh: _load,
            child: CustomScrollView(
              controller: _sc,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 24, 0),
                  sliver: SliverToBoxAdapter(child: Padding(key: _kpiKey, padding: const EdgeInsets.only(bottom: 16), child: _kpis(p, true))),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 24, 24),
                  sliver: SliverToBoxAdapter(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_titleBlock(p), ..._items(p, true)]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final wide = MediaQuery.of(context).size.width >= 900;
    final ready = !loading && d != null;
    _cnt = [_len('userList'), _len('ads'), _len('reports'), _len('pushes'), _len('leads'), null, null];
    return Scaffold(
      appBar: AppBar(title: const Text('Админ-панель')),
      body: loading
          ? Center(child: CircularProgressIndicator(color: p.ac))
          : d == null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(err ?? 'Нет доступа', style: TextStyle(color: p.mu))))
              : (wide ? _wide(p) : _narrow(p)),
      bottomNavigationBar: ready && (tab == 'site' || tab == 'legal') ? _saveBar(p) : null,
    );
  }
}
