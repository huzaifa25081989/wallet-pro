import 'package:flutter/material.dart';
import '../theme.dart';

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});
  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Color theme', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            children: [
              for (int i = 0; i < appThemes.length; i++)
                _Swatch(
                  t: appThemes[i],
                  selected: theme.themeIndex == i,
                  onTap: () => theme.setTheme(i).then((_) => setState(() {})),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Mode', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('Auto')),
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Dark')),
            ],
            selected: {theme.mode},
            onSelectionChanged: (s) => theme.setMode(s.first).then((_) => setState(() {})),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(Icons.palette, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      'Theme "${theme.current.name}" applies instantly across the whole app.',
                      style: TextStyle(color: cs.outline)),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final AppTheme t;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch({required this.t, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [t.seed, t.accent]),
          borderRadius: BorderRadius.circular(16),
          border: selected
              ? Border.all(color: Colors.white, width: 3)
              : null,
          boxShadow: selected
              ? [BoxShadow(color: t.seed.withOpacity(0.5), blurRadius: 8)]
              : null,
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white)
            : const SizedBox.shrink(),
      ),
    );
  }
}
