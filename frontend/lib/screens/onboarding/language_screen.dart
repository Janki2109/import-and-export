import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../auth/auth_visuals.dart';
import '../../providers/providers.dart';

class _Language {
  final String code;
  final String flag;
  final String native;
  final String english;
  const _Language(this.code, this.flag, this.native, this.english);
}

const _languages = <_Language>[
  _Language('en', '🇬🇧', 'English', 'English'),
  _Language('hi', '🇮🇳', 'हिन्दी', 'Hindi'),
  _Language('gu', '🇮🇳', 'ગુજરાતી', 'Gujarati'),
  _Language('mr', '🇮🇳', 'मराठी', 'Marathi'),
  _Language('ta', '🇮🇳', 'தமிழ்', 'Tamil'),
  _Language('te', '🇮🇳', 'తెలుగు', 'Telugu'),
  _Language('kn', '🇮🇳', 'ಕನ್ನಡ', 'Kannada'),
  _Language('ml', '🇮🇳', 'മലയാളം', 'Malayalam'),
  _Language('pa', '🇮🇳', 'ਪੰਜਾਬੀ', 'Punjabi'),
  _Language('bn', '🇧🇩', 'বাংলা', 'Bengali'),
  _Language('ur', '🇵🇰', 'اردو', 'Urdu'),
  _Language('or', '🇮🇳', 'ଓଡ଼ିଆ', 'Odia'),
  _Language('as', '🇮🇳', 'অসমীয়া', 'Assamese'),
  _Language('ne', '🇳🇵', 'नेपाली', 'Nepali'),
  _Language('sd', '🇮🇳', 'سنڌي', 'Sindhi'),
  _Language('kok', '🇮🇳', 'कोंकणी', 'Konkani'),
  _Language('sa', '🇮🇳', 'संस्कृतम्', 'Sanskrit'),
  _Language('fr', '🇫🇷', 'Français', 'French'),
  _Language('de', '🇩🇪', 'Deutsch', 'German'),
  _Language('es', '🇪🇸', 'Español', 'Spanish'),
  _Language('it', '🇮🇹', 'Italiano', 'Italian'),
  _Language('pt', '🇵🇹', 'Português', 'Portuguese'),
  _Language('ru', '🇷🇺', 'Русский', 'Russian'),
  _Language('tr', '🇹🇷', 'Türkçe', 'Turkish'),
  _Language('ar', '🇸🇦', 'العربية', 'Arabic'),
  _Language('fa', '🇮🇷', 'فارسی', 'Persian'),
  _Language('zh', '🇨🇳', '简体中文', 'Chinese (Simplified)'),
  _Language('zh_Hant', '🇹🇼', '繁體中文', 'Chinese (Traditional)'),
  _Language('ja', '🇯🇵', '日本語', 'Japanese'),
  _Language('ko', '🇰🇷', '한국어', 'Korean'),
  _Language('th', '🇹🇭', 'ไทย', 'Thai'),
  _Language('vi', '🇻🇳', 'Tiếng Việt', 'Vietnamese'),
  _Language('id', '🇮🇩', 'Bahasa Indonesia', 'Indonesian'),
  _Language('ms', '🇲🇾', 'Bahasa Melayu', 'Malay'),
  _Language('fil', '🇵🇭', 'Filipino', 'Filipino'),
  _Language('nl', '🇳🇱', 'Nederlands', 'Dutch'),
  _Language('pl', '🇵🇱', 'Polski', 'Polish'),
  _Language('ro', '🇷🇴', 'Română', 'Romanian'),
  _Language('el', '🇬🇷', 'Ελληνικά', 'Greek'),
  _Language('uk', '🇺🇦', 'Українська', 'Ukrainian'),
  _Language('sv', '🇸🇪', 'Svenska', 'Swedish'),
  _Language('no', '🇳🇴', 'Norsk', 'Norwegian'),
  _Language('fi', '🇫🇮', 'Suomi', 'Finnish'),
  _Language('da', '🇩🇰', 'Dansk', 'Danish'),
  _Language('hu', '🇭🇺', 'Magyar', 'Hungarian'),
  _Language('cs', '🇨🇿', 'Čeština', 'Czech'),
  _Language('sk', '🇸🇰', 'Slovenčina', 'Slovak'),
  _Language('he', '🇮🇱', 'עברית', 'Hebrew'),
  _Language('sw', '🇰🇪', 'Kiswahili', 'Swahili'),
];

/// Premium language picker — large rounded cards (flag + native + English name), tap
/// animation, and an animated Continue button. Persists the choice via [LocaleProvider]
/// (SharedPreferences — same key the app already used). English and Hindi have full
/// translations wired today; every other language is fully selectable and remembered, and
/// will render natively the moment its ARB file is added — until then the app shows English
/// rather than a broken mix of languages.
class LanguageScreen extends ConsumerStatefulWidget {
  /// True when opened from Settings ("Change Language") rather than the first-launch flow —
  /// changes only where Continue leads: back to Settings instead of onward to Login.
  final bool isSettingsChange;
  const LanguageScreen({super.key, this.isSettingsChange = false});
  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen> {
  String? _selected = 'en';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final current = ref.read(localeProvider).languageCode;
    if (current != null) _selected = current;
  }

  Future<void> _continue() async {
    if (_selected == null || _saving) return;
    setState(() => _saving = true);
    await ref.read(localeProvider).setLanguage(_selected!);
    if (widget.isSettingsChange) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.onboardingSeenKey, true);
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuthColors.background,
      appBar: widget.isSettingsChange ? AppBar(backgroundColor: Colors.transparent, elevation: 0, foregroundColor: AuthColors.textPrimary) : null,
      body: SafeArea(
        top: !widget.isSettingsChange,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Choose Your Language', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: AuthColors.textPrimary)),
                  const SizedBox(height: 6),
                  const Text('Select your preferred language to continue', style: TextStyle(color: AuthColors.textSecondary, fontSize: 13.5)),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.35),
                itemCount: _languages.length,
                itemBuilder: (context, i) {
                  final lang = _languages[i];
                  return _LanguageCard(
                    language: lang,
                    selected: _selected == lang.code,
                    onTap: () => setState(() => _selected = lang.code),
                  );
                },
              ),
            ),
            AnimatedSlide(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              offset: _selected != null ? Offset.zero : const Offset(0, 0.3),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 260),
                opacity: _selected != null ? 1 : 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 22),
                  child: GradientButton(
                    label: _saving ? 'Please wait...' : 'Continue',
                    icon: Icons.arrow_forward_rounded,
                    loading: _saving,
                    onPressed: _continue,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageCard extends StatefulWidget {
  final _Language language;
  final bool selected;
  final VoidCallback onTap;
  const _LanguageCard({required this.language, required this.selected, required this.onTap});

  @override
  State<_LanguageCard> createState() => _LanguageCardState();
}

class _LanguageCardState extends State<_LanguageCard> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 140), lowerBound: 0, upperBound: 0.06);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.language;
    final selected = widget.selected;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.scale(scale: 1 - _c.value, child: child),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTapDown: (_) => _c.forward(),
          onTapCancel: () => _c.reverse(),
          onTap: () async {
            await _c.forward();
            await _c.reverse();
            widget.onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AuthColors.primary.withValues(alpha: 0.08) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: selected ? AuthColors.primary : Colors.grey.shade200, width: selected ? 1.6 : 1),
              boxShadow: [BoxShadow(color: selected ? AuthColors.primary.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.03), blurRadius: selected ? 14 : 8, offset: const Offset(0, 4))],
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(lang.flag, style: const TextStyle(fontSize: 30)),
                    const SizedBox(height: 6),
                    Text(lang.native, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(lang.english, textAlign: TextAlign.center, style: const TextStyle(color: AuthColors.textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 200),
                    scale: selected ? 1 : 0,
                    curve: Curves.easeOutBack,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: AuthColors.primary),
                      child: const Icon(Icons.check, size: 13, color: Colors.white),
                    ),
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
