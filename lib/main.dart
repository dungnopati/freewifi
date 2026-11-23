import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/brute_force_engine.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WiFiCrackerApp());
}

class WiFiCrackerApp extends StatelessWidget {
  const WiFiCrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final lightScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1D4ED8),
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B82F6),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'WiFi Password Cracker',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: lightScheme,
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: lightScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkScheme,
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: darkScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
      home: const WiFiCrackerPage(),
    );
  }
}

class WiFiCrackerPage extends StatefulWidget {
  const WiFiCrackerPage({super.key});

  /// Đường dẫn kênh YouTube của ứng dụng.
  static const String youtubeChannelUrl =
      'https://youtube.com/@hellohello-b3o?si=2p-iPYMxKX6DmL_n';
  static const String subscribedKey = 'youtube_subscribed';

  @override
  State<WiFiCrackerPage> createState() => _WiFiCrackerPageState();
}

class _WiFiCrackerPageState extends State<WiFiCrackerPage> {
  final TextEditingController _passwordController = TextEditingController();

  CharsetPreset _selectedCharset = CharsetPreset.full;
  bool _obscurePassword = true;
  bool _subscribed = false;
  bool _loadingPrefs = true;

  bool _isRunning = false;
  bool _wasStopped = false;
  BruteForceSession? _session;
  StreamSubscription<BruteForceProgress>? _subscription;
  BruteForceProgress? _latestProgress;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _checkSubscriptionStatus();
  }

  Future<void> _checkSubscriptionStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _subscribed = prefs.getBool(WiFiCrackerPage.subscribedKey) ?? false;
      _loadingPrefs = false;
    });
  }

  Future<void> _setSubscribed(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(WiFiCrackerPage.subscribedKey, value);
    if (!mounted) return;
    setState(() {
      _subscribed = value;
    });
  }

  Future<void> _launchYouTubeChannel() async {
    final uri = Uri.parse(WiFiCrackerPage.youtubeChannelUrl);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể mở liên kết YouTube trên thiết bị này.'),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lỗi khi mở YouTube. Vui lòng thử lại.'),
        ),
      );
    }
  }

  Future<void> _startDemo() async {
    if (_loadingPrefs) return;

    if (!_subscribed) {
      await _showSubscribeDialog();
      return;
    }

    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() {
        _statusMessage = 'Vui lòng nhập mật khẩu mẫu để bắt đầu mô phỏng.';
        _latestProgress = null;
      });
      return;
    }

    if (password.length > BruteForceEngine.defaultMaxLength) {
      setState(() {
        _statusMessage =
            'Độ dài tối đa hỗ trợ mô phỏng là ${BruteForceEngine.defaultMaxLength} ký tự.';
        _latestProgress = null;
      });
      return;
    }

    final unsupported = BruteForceEngine.findUnsupportedCharacters(
      password,
      _selectedCharset.chars,
    );
    if (unsupported.isNotEmpty) {
      setState(() {
        _statusMessage =
            'Mật khẩu chứa ký tự không có trong bộ ký tự đã chọn: ${unsupported.join(', ')}. '
            'Hãy chuyển sang chế độ ký tự phù hợp.';
        _latestProgress = null;
      });
      return;
    }

    await _stopDemo(userRequested: false);

    setState(() {
      _isRunning = true;
      _wasStopped = false;
      _statusMessage = 'Đang chạy thuật toán brute-force trên tiến trình nền...';
      _latestProgress = const BruteForceProgress(
        attempts: 0,
        currentGuess: '',
        currentLength: 1,
        elapsedMs: 0,
      );
    });

    final session = await BruteForceEngine.startIsolate(
      target: password,
      charset: _selectedCharset.chars,
      maxLength: BruteForceEngine.defaultMaxLength,
    );
    if (!mounted) {
      session.cancel();
      return;
    }

    _session = session;
    _subscription = session.stream.listen(
      (progress) {
        if (!mounted) return;
        setState(() {
          _latestProgress = progress;
          if (progress.isDone) {
            _isRunning = false;
            if (progress.errorMessage != null) {
              _statusMessage = progress.errorMessage!;
            } else if (progress.found) {
              _statusMessage =
                  'Đã khớp mật khẩu "${progress.foundPassword}" sau ${_formatNumber(progress.attempts)} lần thử!';
            } else {
              _statusMessage =
                  'Không tìm thấy sau ${_formatNumber(progress.attempts)} lần thử.';
            }
          }
        });
      },
      onDone: () {
        if (!mounted) return;
        if (_isRunning) {
          setState(() => _isRunning = false);
        }
      },
    );
  }

  Future<void> _stopDemo({bool userRequested = true}) async {
    await _subscription?.cancel();
    _subscription = null;
    _session?.cancel();
    _session = null;

    if (userRequested && mounted) {
      setState(() {
        _isRunning = false;
        _wasStopped = true;
        final attempts = _latestProgress?.attempts ?? 0;
        _statusMessage =
            'Đã dừng mô phỏng tại ${_formatNumber(attempts)} lần thử.';
      });
    }
  }

  Future<void> _showSubscribeDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.play_circle_filled_rounded, color: Colors.red),
              SizedBox(width: 8),
              Expanded(child: Text('Đăng ký kênh YouTube')),
            ],
          ),
          content: const Text(
            'Để sử dụng tính năng mô phỏng dò tìm mật khẩu, vui lòng đăng ký kênh YouTube của chúng tôi. '
            'Sau khi đăng ký xong, nhấn "Đã đăng ký" để mở khóa vĩnh viễn trên thiết bị này.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Hủy'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                _launchYouTubeChannel();
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Đăng ký ngay'),
            ),
            FilledButton(
              key: const Key('confirm_subscribed_button'),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _setSubscribed(true);
                if (mounted && _passwordController.text.isNotEmpty) {
                  await _startDemo();
                }
              },
              child: const Text('Đã đăng ký'),
            ),
          ],
        );
      },
    );
  }

  String _formatNumber(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final remaining = s.length - i;
      buf.write(s[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buf.write(',');
      }
    }
    return buf.toString();
  }

  String _formatKeyspace(double count) {
    if (count < 1e3) return count.toStringAsFixed(0);
    if (count < 1e6) return '${(count / 1e3).toStringAsFixed(1)} nghìn';
    if (count < 1e9) return '${(count / 1e6).toStringAsFixed(1)} triệu';
    if (count < 1e12) return '${(count / 1e9).toStringAsFixed(1)} tỷ';
    return count.toStringAsExponential(2);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _session?.cancel();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progress = _latestProgress;
    final inputLen = _passwordController.text.length;
    final estimatedSpace = inputLen > 0
        ? BruteForceEngine.estimateCombinations(
            _selectedCharset.chars.length,
            inputLen,
          )
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi Password Cracker'),
        actions: [
          if (!_subscribed)
            IconButton(
              icon: const Icon(Icons.play_circle_fill, color: Colors.red),
              onPressed: _launchYouTubeChannel,
              tooltip: 'Mở kênh YouTube',
            )
          else
            IconButton(
              icon: const Icon(Icons.verified_rounded, color: Colors.green),
              tooltip: 'Đã xác nhận đăng ký YouTube (nhấn để đặt lại)',
              onPressed: () async {
                await _setSubscribed(false);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã đặt lại trạng thái đăng ký YouTube.'),
                  ),
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.security_rounded,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Mô phỏng thuật toán brute-force ngoại tuyến để kiểm tra độ mạnh mật khẩu. '
                          'Ứng dụng không kết nối hay xâm nhập mạng Wi-Fi thật.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (!_loadingPrefs && !_subscribed) ...[
                Card(
                  color: Colors.amber.withValues(alpha: 0.16),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(Icons.subscriptions_rounded,
                            color: Colors.amber),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Cần đăng ký kênh YouTube 1 lần để mở khóa tính năng mô phỏng.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _showSubscribeDialog,
                          child: const Text('Mở khóa'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cấu hình mô phỏng',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('password_input_field'),
                        controller: _passwordController,
                        enabled: !_isRunning,
                        obscureText: _obscurePassword,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Nhập mật khẩu mẫu (1–12 ký tự)',
                          hintText: 'Ví dụ: a1b hoặc 1234',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Hiện mật khẩu'
                                : 'Ẩn mật khẩu',
                            onPressed: () {
                              setState(
                                () => _obscurePassword = !_obscurePassword,
                              );
                            },
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Bộ ký tự thử nghiệm (${_selectedCharset.chars.length} ký tự)',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: CharsetPreset.values.map((preset) {
                          return ChoiceChip(
                            label: Text(preset.label),
                            selected: _selectedCharset == preset,
                            onSelected: _isRunning
                                ? null
                                : (_) =>
                                    setState(() => _selectedCharset = preset),
                          );
                        }).toList(),
                      ),
                      if (inputLen > 0) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Không gian tổ hợp tối đa ($inputLen ký tự): ~${_formatKeyspace(estimatedSpace)} tổ hợp',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              key: const Key('start_crack_button'),
                              onPressed: _isRunning ? null : _startDemo,
                              icon: _isRunning
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.search_rounded),
                              label: Text(
                                _isRunning
                                    ? 'Đang dò tìm...'
                                    : 'Dò tìm mật khẩu',
                              ),
                              style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          if (_isRunning) ...[
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              key: const Key('stop_crack_button'),
                              onPressed: () => _stopDemo(),
                              icon: const Icon(Icons.stop_rounded),
                              label: const Text('Dừng'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colorScheme.error,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_statusMessage.isNotEmpty || progress != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              progress?.found == true
                                  ? Icons.check_circle_rounded
                                  : _wasStopped
                                      ? Icons.pause_circle_outline_rounded
                                      : _isRunning
                                          ? Icons.bolt_rounded
                                          : Icons.info_outline_rounded,
                              color: progress?.found == true
                                  ? Colors.green
                                  : colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Kết quả & Tiến trình',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_statusMessage.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            _statusMessage,
                            key: const Key('result_status_text'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (progress != null) ...[
                          const SizedBox(height: 12),
                          if (_isRunning) const LinearProgressIndicator(),
                          const SizedBox(height: 12),
                          _MetricRow(
                            label: 'Số tổ hợp đã thử',
                            value: _formatNumber(progress.attempts),
                          ),
                          _MetricRow(
                            label: 'Độ dài đang quét',
                            value: '${progress.currentLength} ký tự',
                          ),
                          if (progress.currentGuess.isNotEmpty)
                            _MetricRow(
                              label: progress.found
                                  ? 'Mật khẩu tìm được'
                                  : 'Mẫu đang thử',
                              value: progress.currentGuess,
                            ),
                          _MetricRow(
                            label: 'Thời gian chạy',
                            value:
                                '${progress.elapsedSeconds.toStringAsFixed(3)} giây',
                          ),
                          _MetricRow(
                            label: 'Tốc độ ước tính',
                            value:
                                '${_formatNumber(progress.attemptsPerSecond.round())} thử/giây',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
