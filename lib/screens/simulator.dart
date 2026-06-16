import 'dart:math';
import 'package:flutter/material.dart';
import '../widgets.dart';

class SimulatorScreen extends StatefulWidget {
  const SimulatorScreen({super.key});
  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends State<SimulatorScreen> {
  String mode = 'save';

  // savings
  final startCtl = TextEditingController(text: '0');
  final monthlyCtl = TextEditingController(text: '20000');
  final returnCtl = TextEditingController(text: '0');
  final targetCtl = TextEditingController(text: '15000000');
  final yearsCtl = TextEditingController(text: '5');

  // purchase
  final priceCtl = TextEditingController(text: '4000000');
  final downCtl = TextEditingController(text: '1000000');
  final rateCtl = TextEditingController(text: '20');
  final termCtl = TextEditingController(text: '5');
  final budgetCtl = TextEditingController(text: '60000');

  double _n(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '')) ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('What-if Simulator')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'save', label: Text('Save for goal'), icon: Icon(Icons.savings)),
              ButtonSegment(value: 'buy', label: Text('Buy / loan'), icon: Icon(Icons.directions_car)),
            ],
            selected: {mode},
            onSelectionChanged: (s) => setState(() => mode = s.first),
          ),
          const SizedBox(height: 16),
          if (mode == 'save') ..._save() else ..._buy(),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c, {String? suffix}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              labelText: label, suffixText: suffix, border: const OutlineInputBorder()),
        ),
      );

  List<Widget> _save() {
    final start = _n(startCtl), monthly = _n(monthlyCtl);
    final r = _n(returnCtl) / 100 / 12;
    final months = (_n(yearsCtl) * 12).round();
    final target = _n(targetCtl);
    // future value of current + annuity
    double fv;
    if (r == 0) {
      fv = start + monthly * months;
    } else {
      fv = start * pow(1 + r, months) + monthly * ((pow(1 + r, months) - 1) / r);
    }
    final reachable = fv >= target;
    // required monthly to hit target
    double req;
    if (r == 0) {
      req = months == 0 ? 0 : (target - start) / months;
    } else {
      req = (target - start * pow(1 + r, months)) * r / (pow(1 + r, months) - 1);
    }
    return [
      _field('Starting amount', startCtl, suffix: kCur),
      _field('Monthly saving', monthlyCtl, suffix: kCur),
      _field('Expected annual return', returnCtl, suffix: '%'),
      _field('Years', yearsCtl),
      _field('Target amount', targetCtl, suffix: kCur),
      const SizedBox(height: 8),
      _result(
        reachable ? Colors.green : Colors.orange,
        reachable ? Icons.check_circle : Icons.info,
        reachable ? 'On track!' : 'Shortfall',
        [
          'Projected in ${_n(yearsCtl).toStringAsFixed(0)} years: ${money(fv)}',
          'Target: ${money(target)}',
          if (!reachable) 'You need about ${money(req < 0 ? 0 : req)}/month to reach it',
          if (reachable) 'You will exceed target by ${money(fv - target)}',
        ],
      ),
    ];
  }

  List<Widget> _buy() {
    final price = _n(priceCtl), down = _n(downCtl);
    final principal = (price - down).clamp(0, double.infinity).toDouble();
    final r = _n(rateCtl) / 100 / 12;
    final n = (_n(termCtl) * 12).round();
    double pmt;
    if (n == 0) {
      pmt = principal;
    } else if (r == 0) {
      pmt = principal / n;
    } else {
      pmt = principal * r * pow(1 + r, n) / (pow(1 + r, n) - 1);
    }
    final totalPaid = pmt * n;
    final interest = totalPaid - principal;
    final budget = _n(budgetCtl);
    final affordable = pmt <= budget;
    return [
      _field('Price', priceCtl, suffix: kCur),
      _field('Down payment', downCtl, suffix: kCur),
      _field('Annual interest rate', rateCtl, suffix: '%'),
      _field('Loan term (years)', termCtl),
      _field('Your monthly budget for this', budgetCtl, suffix: kCur),
      const SizedBox(height: 8),
      _result(
        affordable ? Colors.green : Colors.red,
        affordable ? Icons.check_circle : Icons.warning,
        affordable ? 'Affordable' : 'Over budget',
        [
          'Loan amount: ${money(principal)}',
          'Monthly installment: ${money(pmt)}',
          'Total interest over term: ${money(interest)}',
          'Total paid: ${money(totalPaid + down)}',
          affordable
              ? 'Fits within your ${money(budget)} budget'
              : 'Exceeds your budget by ${money(pmt - budget)}/month',
        ],
      ),
    ];
  }

  Widget _result(Color color, IconData icon, String title, List<String> lines) => Card(
        color: color.withOpacity(0.10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            ]),
            const SizedBox(height: 8),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(l),
              ),
          ]),
        ),
      );
}
