import 'package:flutter/material.dart';
import 'api.dart';
import 'icons.dart';
import 'models.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

// Продвижение объявления, как на сайте (promoSheet): «Выделение цветом» на 3 варианта срока и «Поднять в начало» раз в сутки.
// Цены и сроки приходят с сервера (promoCfg), пока всё бесплатно — тогда цена зачёркнута и написано «Бесплатно».
// ad == null и fresh == true — объявление только что опубликовано (поднять его можно будет через сутки).
Future<void> showPromoSheet(BuildContext context, {Ad? ad, String id = '', String title = '', bool fresh = false}) async {
  Map<String, dynamic> cfg;
  try {
    cfg = await Api.call('promoCfg');
  } catch (e) {
    if (context.mounted) toast(context, S.i.fail(e), err: true);
    return;
  }
  if (!context.mounted) return;
  final p = pal(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: p.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (c) => _PromoSheet(cfg: cfg, ad: ad, id: ad?.id ?? id, title: title.isNotEmpty ? title : (ad?.title ?? ''), fresh: fresh),
  );
}

const _months = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];

class _PromoSheet extends StatefulWidget {
  final Map<String, dynamic> cfg;
  final Ad? ad;
  final String id, title;
  final bool fresh;
  const _PromoSheet({required this.cfg, required this.ad, required this.id, required this.title, required this.fresh});
  @override
  State<_PromoSheet> createState() => _PromoSheetState();
}

class _PromoSheetState extends State<_PromoSheet> {
  int hl = -1; // выбранный вариант срока выделения
  bool bump = false;
  bool busy = false;

  Map<String, dynamic> _m(String k) => widget.cfg[k] is Map ? Map<String, dynamic>.from(widget.cfg[k] as Map) : <String, dynamic>{};
  bool get free => widget.cfg['free'] == true;
  List<Map<String, dynamic>> get _opts {
    final o = _m('hl')['opts'];
    if (o is! List) return [];
    return o.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  int _n(dynamic v) => v is num ? v.toInt() : int.tryParse((v ?? '').toString()) ?? 0;
  int get _bumpPrice => _n(_m('bump')['price']);

  // сколько мс осталось до следующего подъёма: раз в сутки с момента публикации или последнего подъёма
  int get _wait {
    final a = widget.ad;
    if (a == null) return widget.fresh ? 86400000 : 0;
    final last = a.up > a.ts ? a.up : a.ts;
    final w = 86400000 - (DateTime.now().millisecondsSinceEpoch - last);
    return w > 0 ? w : 0;
  }

  Future<void> _connect() async {
    if (busy) return;
    setState(() => busy = true);
    final opts = _opts;
    var ok = 0;
    try {
      if (hl >= 0 && hl < opts.length) {
        await Api.call('promo', {'id': widget.id, 'kind': 'hl', 'days': _n(opts[hl]['days'])});
        hl = -1;
        ok++;
      }
      if (bump && _wait == 0) {
        await Api.call('promo', {'id': widget.id, 'kind': 'bump'});
        bump = false;
        ok++;
      }
      if (!mounted) return;
      toast(context, ok > 1 ? 'Услуги подключены' : 'Услуга подключена');
      await S.i.loadAds();
      S.i.bumpCab();
      if (mounted) Navigator.pop(context);
      return;
    } catch (e) {
      if (mounted) toast(context, S.i.fail(e), err: true);
    }
    if (ok > 0) {
      await S.i.loadAds();
      S.i.bumpCab();
    }
    if (mounted) setState(() => busy = false);
  }

  Widget _price(Pal p, int n, {bool big = false}) {
    if (free) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$n ₽', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.mu, decoration: TextDecoration.lineThrough)),
        Text('Бесплатно', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.ok)),
      ]);
    }
    return Text('$n ₽', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.tx));
  }

  Widget _head(Pal p, String k, String icon) {
    final c = _m(k);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: p.ac.withOpacity(.16), borderRadius: BorderRadius.circular(14)),
          child: Center(child: Ico(icon, size: 22, color: p.ac)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((c['name'] ?? '').toString(), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.tx)),
            const SizedBox(height: 2),
            Text((c['info'] ?? '').toString(), style: TextStyle(fontSize: 13, height: 1.35, color: p.mu)),
          ]),
        ),
      ]),
    );
  }

  Widget _opt(Pal p, {required bool on, required VoidCallback f, required String label, required int price}) {
    return Tap(
      onTap: busy ? () {} : f,
      scale: .96,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: on ? p.ac.withOpacity(.14) : p.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? p.ac : p.bd, width: 1.5),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.tx)),
          const SizedBox(height: 2),
          _price(p, price),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final opts = _opts;
    final wait = _wait;
    final hrs = (wait / 3600000).ceil();
    final until = widget.ad?.hlUntil ?? 0;
    final active = until > DateTime.now().millisecondsSinceEpoch;
    final ud = DateTime.fromMillisecondsSinceEpoch(until);
    final hlCfg = _m('hl'), bpCfg = _m('bump');
    final selPrice = (hl >= 0 && hl < opts.length ? _n(opts[hl]['price']) : 0) + (bump && wait == 0 ? _bumpPrice : 0);
    final n = (hl >= 0 ? 1 : 0) + (bump && wait == 0 ? 1 : 0);
    final can = n > 0 && !busy;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .92),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 10),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: p.bd, borderRadius: BorderRadius.circular(4))),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.fresh ? 'Объявление опубликовано' : 'Продвижение', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: p.tx)),
              const SizedBox(height: 4),
              Text(
                widget.fresh ? 'Хотите, чтобы его увидело больше людей? Выберите услуги или пропустите.' : widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, height: 1.35, color: p.mu),
              ),
              const SizedBox(height: 12),
              // выделение цветом
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(p.ac.withOpacity(.08), p.bg2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Color.alphaBlend(p.ac.withOpacity(.45), p.bd)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _head(p, 'hl', 'star'),
                  if (active)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        Ico('clock', size: 14, color: p.ok),
                        const SizedBox(width: 6),
                        Text('Действует до ${ud.day} ${_months[ud.month - 1]}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.ok)),
                      ]),
                    ),
                  Row(children: [
                    for (var i = 0; i < opts.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _opt(p, on: hl == i, f: () => setState(() => hl = hl == i ? -1 : i), label: '${_n(opts[i]['days'])} дн.', price: _n(opts[i]['price'])),
                      ),
                    ],
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              // поднять в начало
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: p.bg2, borderRadius: BorderRadius.circular(20), border: Border.all(color: p.bd)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _head(p, 'bump', 'pub'),
                  if (wait > 0)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(14)),
                      child: Text('Доступно через $hrs ч', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.mu)),
                    )
                  else
                    _opt(p, on: bump, f: () => setState(() => bump = !bump), label: 'Раз в сутки', price: _n(bpCfg['price'])),
                ]),
              ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.bd))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (n > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Expanded(child: Text('Выбрано: $n', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.tx))),
                  if (free)
                    Row(children: [
                      Text('$selPrice ₽', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.mu, decoration: TextDecoration.lineThrough)),
                      const SizedBox(width: 6),
                      Text('Бесплатно', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.ok)),
                    ])
                  else
                    Text('$selPrice ₽', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: p.tx)),
                ]),
              ),
            GradBtn(busy ? 'Подключаем…' : (n > 0 ? 'Подключить' : 'Выберите услугу'), height: 52, radius: 16, busy: busy, onTap: can ? _connect : null),
            if (widget.fresh)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: Text('Пропустить', style: TextStyle(color: p.mu, fontWeight: FontWeight.w700, fontSize: 14.5)),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
