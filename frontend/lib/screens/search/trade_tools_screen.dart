import 'package:flutter/material.dart';
import 'hs_code_search_screen.dart';
import 'gst_rates_screen.dart';
import 'country_search_screen.dart';
import 'ai_product_search_screen.dart';
import 'duty_calculator_screen.dart';
import 'freight_calculator_screen.dart';
import 'landed_cost_calculator_screen.dart';

/// Hub screen linking every search & calculator tool — HS Code, GST, Country/Policy,
/// AI Product Search, and the Duty/Freight/Landed-Cost calculators. Premium grid layout;
/// every entry still routes to the same existing screens as before.
class TradeToolsScreen extends StatelessWidget {
  const TradeToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tools = <_Tool>[
      _Tool('AI Product Search', 'Describe a product, get matching HS codes', Icons.auto_awesome_outlined, const [Color(0xFF6D28D9), Color(0xFF9333EA)], const AIProductSearchScreen()),
      _Tool('HS Code Search', 'Look up HS codes, duty & IGST rates', Icons.qr_code_2_outlined, const [Color(0xFF0B3D91), Color(0xFF1857C4)], const HSCodeSearchScreen()),
      _Tool('GST Rate Slabs', 'Standard GST rate categories', Icons.receipt_long_outlined, const [Color(0xFF0EA5A0), Color(0xFF14B8A6)], const GSTRatesScreen()),
      _Tool('Country Search', 'Destination countries & trade policy notes', Icons.public_outlined, const [Color(0xFF1B8A5A), Color(0xFF22C55E)], const CountrySearchScreen()),
      _Tool('Duty Calculator', 'Estimate BCD + SWS + IGST for an HS code', Icons.calculate_outlined, const [Color(0xFFEA580C), Color(0xFFFF7A00)], const DutyCalculatorScreen()),
      _Tool('Freight Calculator', 'Estimate air/sea/road freight cost', Icons.local_shipping_outlined, const [Color(0xFF2563EB), Color(0xFF3B82F6)], const FreightCalculatorScreen()),
      _Tool('Landed Cost Calculator', 'FOB → CIF → total landed cost', Icons.summarize_outlined, const [Color(0xFFDB2777), Color(0xFFEC4899)], const LandedCostCalculatorScreen()),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Trade Tools')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.92,
        ),
        itemCount: tools.length,
        itemBuilder: (context, i) {
          final t = tools[i];
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 200 + (i * 40).clamp(0, 320)),
            curve: Curves.easeOut,
            builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: child)),
            child: _ToolCard(tool: t),
          );
        },
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final _Tool tool;
  const _ToolCard({required this.tool});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => tool.screen)),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: tool.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: tool.gradient.first.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(13)),
                  child: Icon(tool.icon, color: Colors.white, size: 22),
                ),
                const Spacer(),
                Text(tool.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(tool.subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 10.5, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                    child: const Icon(Icons.arrow_forward, color: Colors.white, size: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tool {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final Widget screen;
  _Tool(this.title, this.subtitle, this.icon, this.gradient, this.screen);
}
