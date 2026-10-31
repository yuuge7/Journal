import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/database.dart';
import 'providers.dart';
import 'screens/home_screen.dart';
import 'screens/editor_screen.dart';
import 'services/platform_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const ProviderScope(child: JournalApp()));
}

class JournalApp extends ConsumerStatefulWidget {
  const JournalApp({super.key});
  @override
  ConsumerState<JournalApp> createState() => _JournalAppState();
}

class _JournalAppState extends ConsumerState<JournalApp>
    with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  bool _ready = false;
  bool _locked = false;
  bool _authenticating = false;
  bool _pendingWrite = false;
  String? _lockError;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PlatformService.channel.setMethodCallHandler((call) async {
      if (call.method == 'write') {
        _pendingWrite = true;
        _openPending();
      }
    });
    _initialize();
  }

  Future<void> _initialize() async {
    if (mounted) setState(() => _startupError = null);
    try {
      final db = ref.read(databaseProvider);
      final lock = await db.setting('app_lock') == 'true';
      await PlatformService.secure(await db.setting('secure_screen') == 'true');
      await db.purgeBin();
      final files = await db.select(db.attachments).get();
      await ref
          .read(attachmentServiceProvider)
          .sweep(files.map((a) => a.fileName).toSet());
      _pendingWrite =
          await PlatformService.call<String>('launchAction') == 'write';
      if (!mounted) return;
      setState(() {
        _locked = lock;
        _ready = true;
      });
      _openPending();
    } catch (e) {
      if (mounted) setState(() => _startupError = e.toString());
    }
  }

  void _openPending() {
    if (!_ready || _locked || !_pendingWrite) return;
    _pendingWrite = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _navigator.currentState?.push(
          MaterialPageRoute(builder: (_) => const EditorScreen()),
        );
      }
    });
  }

  Future<void> _unlock({bool deviceCredentialOnly = false}) async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _lockError = null;
    });
    try {
      final authenticated = await PlatformService.authenticate(
        deviceCredentialOnly: deviceCredentialOnly,
      );
      if (authenticated && mounted) {
        setState(() {
          _locked = false;
          _lockError = null;
        });
        _openPending();
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _lockError = e.message ?? "Couldn't unlock Journal.");
      }
    } catch (_) {
      if (mounted) {
        setState(() => _lockError = "Couldn't unlock Journal. Try again.");
      }
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (!_authenticating &&
          ref.read(preferenceProvider('app_lock')).value == 'true') {
        setState(() => _locked = true);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PlatformService.channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(preferenceProvider('theme')).value;
    // Subscribe before the first background event so relocking reads a loaded
    // preference, rather than starting the settings stream while going away.
    ref.listen(preferenceProvider('app_lock'), (_, value) {
      // A device credential activity can background and relock Journal while
      // Settings verifies a request to turn app lock off.
      if (value.value == 'false' && _locked) {
        setState(() {
          _locked = false;
          _lockError = null;
        });
        _openPending();
      }
    });
    ref.listen(preferenceProvider('secure_screen'), (_, value) {
      PlatformService.secure(value.value == 'true');
    });
    ref.listen(insightsProvider, (_, value) {
      final rows = value.value;
      if (rows == null) return;
      final streak = computeStreaks(rows.map((e) => e.entryDate));
      PlatformService.widget(
        streak: streak.current,
        written: rows.any(
          (e) => dayOrdinal(e.entryDate) == dayOrdinal(DateTime.now()),
        ),
      );
    });
    return MaterialApp(
      navigatorKey: _navigator,
      title: 'Journal',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(brightness: Brightness.light),
      darkTheme: buildTheme(brightness: Brightness.dark),
      themeMode: mode == 'light'
          ? ThemeMode.light
          : mode == 'dark'
          ? ThemeMode.dark
          : ThemeMode.system,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: FlutterQuillLocalizations.supportedLocales,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value:
            (Theme.of(context).brightness == Brightness.dark
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark)
                .copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarContrastEnforced: false,
                ),
        child: Stack(
          children: [
            Offstage(offstage: !_ready || _locked, child: child),
            if (!_ready)
              Positioned.fill(
                child: Material(
                  child: Center(
                    child: _startupError == null
                        ? const CircularProgressIndicator()
                        : Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "Couldn't open your journal",
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Your writing is still on this device. Try opening it again.',
                                ),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: _initialize,
                                  child: const Text('Try again'),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            if (_ready && _locked)
              Positioned.fill(
                child: Material(
                  child: SafeArea(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock_outline, size: 36),
                            const SizedBox(height: 16),
                            Text(
                              'Your private notebook',
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Unlock with biometrics or your device screen lock.',
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _authenticating ? null : _unlock,
                              icon: const Icon(Icons.fingerprint),
                              label: const Text('Unlock Journal'),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _authenticating
                                  ? null
                                  : () => _unlock(deviceCredentialOnly: true),
                              icon: const Icon(Icons.pin_outlined),
                              label: const Text('Use device PIN'),
                            ),
                            if (_lockError != null) ...[
                              const SizedBox(height: 12),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _lockError!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
