import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../license.dart';
import '../theme.dart';
import '../widgets.dart';
import 'subscribe.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Widget _step(BuildContext c, IconData i, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(radius: 18, backgroundColor: Theme.of(c).colorScheme.primaryContainer, child: Icon(i, size: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 2),
              Text(body, style: TextStyle(color: Theme.of(c).colorScheme.outline, height: 1.35)),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About ProFinance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(gradient: headerGradient(context), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Text('ProFinance', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text('Your money, beautifully organized. Track spending, accounts, budgets, goals and full reports \u2014 all on your phone.',
                  style: TextStyle(color: Colors.white70)),
            ]),
          ),
          const SizedBox(height: 22),
          Text('How to use it', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          _step(context, Icons.account_balance_wallet, 'Add your accounts',
              'Go to Accounts and add your cash, bank, card, or even a person you lend to. Set the current balance so everything matches real life.'),
          _step(context, Icons.add, 'Record money in one voucher',
              'Tap the + button. Choose Expense, Income or Transfer, pick the account you paid from, choose a category and amount, then Save. To split one payment across many categories or people, tap "Add split line" \u2014 it all stays in a single voucher.'),
          _step(context, Icons.mic, 'Or just speak',
              'Tap the microphone on the home screen and say something like "expense 500 groceries". ProFinance fills it in for you.'),
          _step(context, Icons.pie_chart, 'See where money goes',
              'Analytics shows income vs expense, top categories and trends. The Detailed report gives a full debit / credit / balance statement you can export to PDF or Excel.'),
          _step(context, Icons.savings, 'Set goals & budgets',
              'Create a savings goal and take the Daily Save Challenge to build a streak. Budgets warn you before you overspend.'),
          _step(context, Icons.account_tree, 'Organize your categories',
              'In More \u2192 Chart of Accounts, group your categories under Expense and Income classes using the simple dropdown.'),
          _step(context, Icons.cloud_done, 'Back up safely',
              'Turn on cloud backup so your data is safe, and use Family Connect to share with your spouse or family.'),
          const Divider(height: 30),
          Text('How to subscribe', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(
            'Every new user gets the full app free for $kTrialDays days \u2014 no limits. After that, keep going with a membership:\n\n'
            '\u2022 1 Month \u2014 \$10\n\u2022 1 Year \u2014 \$30  (best for most people)\n\u2022 2 Years \u2014 \$50  (best value)\n\n'
            'Open the Membership tab, pick a plan and tap "I paid \u2014 email my App ID". Send the payment, and you\u2019ll get an activation code that unlocks this device. Paste it in and you\u2019re premium.',
            style: TextStyle(height: 1.4, color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscribeScreen())),
            icon: const Icon(Icons.workspace_premium),
            label: const Text('Open Membership'),
          ),
          const SizedBox(height: 24),
          Center(child: Text('Made by Muhammad Huzaifa', style: TextStyle(color: Theme.of(context).colorScheme.outline))),
          const SizedBox(height: 6),
          Center(
            child: GestureDetector(
              onLongPress: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OwnerSignScreen())),
              child: Text('App ID ${license.appId}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});
  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  String kind = 'Feedback';
  final msgCtl = TextEditingController();

  Future<void> _send() async {
    if (msgCtl.text.trim().isEmpty) {
      snack(context, 'Please write your message first');
      return;
    }
    final subject = Uri.encodeComponent('ProFinance $kind');
    final body = Uri.encodeComponent('${msgCtl.text.trim()}\n\n---\nApp ID: ${license.appId}');
    final uri = Uri.parse('mailto:$kOwnerEmail?subject=$subject&body=$body');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) snack(context, 'No email app found. Write to $kOwnerEmail');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feedback & Complaints')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('We\u2019d love to hear from you. Tell us what you love, what\u2019s broken, or what you wish ProFinance could do.'),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Feedback', label: Text('Feedback'), icon: Icon(Icons.thumb_up_alt_outlined)),
              ButtonSegment(value: 'Complaint', label: Text('Complaint'), icon: Icon(Icons.report_gmailerrorred_outlined)),
              ButtonSegment(value: 'Idea', label: Text('Idea'), icon: Icon(Icons.lightbulb_outline)),
            ],
            selected: {kind},
            onSelectionChanged: (s) => setState(() => kind = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: msgCtl,
            maxLines: 7,
            decoration: const InputDecoration(
              labelText: 'Your message',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _send,
            icon: const Icon(Icons.send),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            label: const Text('Send to developer'),
          ),
          const SizedBox(height: 12),
          Center(child: Text('or email $kOwnerEmail', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12))),
        ],
      ),
    );
  }
}
