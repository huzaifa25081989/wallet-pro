import 'package:flutter/material.dart';
import '../theme.dart';
import 'accounts.dart';
import 'family.dart';
import 'loans.dart';
import 'split_bill.dart';
import 'split_expense.dart';
import 'txn_edit.dart';

class _Opt {
  final IconData icon;
  final String label;
  final String sub;
  final List<Color> grad;
  final Widget Function() screen;
  const _Opt(this.icon, this.label, this.sub, this.grad, this.screen);
}

class AddHubScreen extends StatelessWidget {
  const AddHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final record = <_Opt>[
      _Opt(Icons.south_west, 'Income', 'Money received', const [Color(0xFF11998E), Color(0xFF38EF7D)],
          () => const TxnEdit(initialType: 'income')),
      _Opt(Icons.north_east, 'Expense', 'Money spent', const [Color(0xFFEB3349), Color(0xFFF45C43)],
          () => const TxnEdit(initialType: 'expense')),
      _Opt(Icons.swap_horiz, 'Transfer', 'Between accounts', const [Color(0xFF1A2980), Color(0xFF26D0CE)],
          () => const TxnEdit(initialType: 'transfer')),
      _Opt(Icons.mic, 'Voice entry', 'Speak to add', const [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
          () => const TxnEdit(autoVoice: true)),
    ];
    final split = <_Opt>[
      _Opt(Icons.call_split, 'Split expense', 'One payment, many categories', const [Color(0xFF36D1DC), Color(0xFF5B86E5)],
          () => const SplitExpenseScreen()),
      _Opt(Icons.groups, 'Split a bill', 'With friends, they owe you', const [Color(0xFFFF8008), Color(0xFFFFC837)],
          () => const SplitBillScreen()),
    ];
    final more = <_Opt>[
      _Opt(Icons.handshake, 'Loan / Debt', 'Lend, borrow & repay', const [Color(0xFF614385), Color(0xFF516395)],
          () => const LoansScreen()),
      _Opt(Icons.family_restroom, 'Family Connect', 'Share & bill family', const [Color(0xFFc94b4b), Color(0xFF4b134f)],
          () => const FamilyScreen()),
      _Opt(Icons.account_balance_wallet, 'New account', 'Add a wallet or person', const [Color(0xFFf7971e), Color(0xFFffd200)],
          () => const AccountEdit()),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Add a record')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          _section(context, 'Record', record),
          const SizedBox(height: 18),
          _section(context, 'Split', split),
          const SizedBox(height: 18),
          _section(context, 'More', more),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<_Opt> opts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.55,
          children: [for (final o in opts) _tile(context, o)],
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, _Opt o) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (_) => o.screen()));
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: o.grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: o.grad.last.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.22), shape: BoxShape.circle),
              child: Icon(o.icon, color: Colors.white, size: 22),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 2),
              Text(o.sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ]),
          ],
        ),
      ),
    );
  }
}
