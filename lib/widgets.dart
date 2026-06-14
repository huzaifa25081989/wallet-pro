import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:intl/intl.dart';

const kCur = 'Rs';
final _nf = NumberFormat('#,##0.##');

String fmt(num v) => _nf.format(v);
String money(num v) => '$kCur ${_nf.format(v)}';

IconData iconOf(Object? codePoint) =>
    IconData((codePoint as int?) ?? Icons.category.codePoint, fontFamily: 'MaterialIcons');

const pickIcons = <IconData>[
  Icons.account_balance, Icons.account_balance_wallet, Icons.savings, Icons.credit_card,
  Icons.trending_up, Icons.attach_money, Icons.payments, Icons.currency_exchange,
  Icons.restaurant, Icons.fastfood, Icons.local_cafe, Icons.shopping_cart,
  Icons.shopping_bag, Icons.storefront, Icons.directions_car, Icons.local_gas_station,
  Icons.directions_bus, Icons.flight, Icons.home, Icons.apartment,
  Icons.receipt_long, Icons.lightbulb, Icons.water_drop, Icons.wifi,
  Icons.phone_android, Icons.local_hospital, Icons.medication, Icons.fitness_center,
  Icons.school, Icons.menu_book, Icons.movie, Icons.sports_esports,
  Icons.music_note, Icons.card_giftcard, Icons.volunteer_activism, Icons.mosque,
  Icons.family_restroom, Icons.child_care, Icons.pets, Icons.work,
  Icons.build, Icons.laptop, Icons.beach_access, Icons.celebration,
  Icons.local_laundry_service, Icons.checkroom, Icons.spa, Icons.category,
];

Future<IconData?> pickIcon(BuildContext context) => showModalBottomSheet<IconData>(
      context: context,
      builder: (c) => SafeArea(
        child: GridView.count(
          crossAxisCount: 6,
          padding: const EdgeInsets.all(16),
          children: [
            for (final i in pickIcons)
              IconButton(icon: Icon(i, size: 28), onPressed: () => Navigator.pop(c, i)),
          ],
        ),
      ),
    );

Future<Color?> pickColor(BuildContext context, Color initial) async {
  Color sel = initial;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Pick a color'),
      content: SingleChildScrollView(
        child: ColorPicker(
          pickerColor: initial,
          onColorChanged: (v) => sel = v,
          paletteType: PaletteType.hueWheel,
          enableAlpha: false,
          labelTypes: const [],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('OK')),
      ],
    ),
  );
  return ok == true ? sel : null;
}

Future<bool> confirm(BuildContext context, String title, String msg) async =>
    (await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yes')),
        ],
      ),
    )) ==
    true;

void snack(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// One transaction row, used in Records and Account detail.
class TxnTile extends StatelessWidget {
  final Map<String, Object?> t;
  final Map<int, Map<String, Object?>> cats;
  final Map<int, Map<String, Object?>> accts;
  final VoidCallback? onTap;
  const TxnTile(
      {super.key, required this.t, required this.cats, required this.accts, this.onTap});

  @override
  Widget build(BuildContext context) {
    final type = t['type'] as String? ?? 'expense';
    final cat = cats[t['categoryId']];
    final amt = ((t['amount'] as num?) ?? 0).toDouble();
    final amtColor = type == 'income'
        ? Colors.green
        : type == 'expense'
            ? Colors.red
            : Colors.blue;
    final avColor = type == 'transfer'
        ? Colors.blue
        : Color((cat?['color'] as int?) ?? Colors.grey.value);
    final ic = type == 'transfer' ? Icons.swap_horiz : iconOf(cat?['icon']);
    final note = (t['note'] as String?) ?? '';
    final catName = (cat?['name'] as String?) ?? 'Uncategorized';
    final title = note.isNotEmpty ? note : (type == 'transfer' ? 'Transfer' : catName);
    final String sub;
    if (type == 'transfer') {
      sub =
          '${accts[t['accountId']]?['name'] ?? '?'} \u2192 ${accts[t['toAccountId']]?['name'] ?? '?'}';
    } else {
      sub = '$catName \u2022 ${accts[t['accountId']]?['name'] ?? '?'}';
    }
    final sign = type == 'income' ? '+' : type == 'expense' ? '\u2212' : '';
    return ListTile(
      leading: CircleAvatar(backgroundColor: avColor, child: Icon(ic, color: Colors.white, size: 20)),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text('$sign${money(amt)}',
          style: TextStyle(color: amtColor, fontWeight: FontWeight.bold)),
      onTap: onTap,
    );
  }
}
