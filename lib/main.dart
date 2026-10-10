import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const OnlyDmApp());
}

class OnlyDmApp extends StatelessWidget {
  const OnlyDmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Only DM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE1306C), // Instagram brand accent
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.white,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE1306C),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const InstagramDmScreen(),
    );
  }
}

class InstagramDmScreen extends StatefulWidget {
  const InstagramDmScreen({super.key});

  @override
  State<InstagramDmScreen> createState() => _InstagramDmScreenState();
}

class _InstagramDmScreenState extends State<InstagramDmScreen> {
  static const String _dmInboxUrl = 'https://www.instagram.com/direct/inbox/';

  late final WebViewController _controller;
  int _loadingProgress = 0;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  // JavaScript snippet to block dopamine elements (Home, Explore, Reels buttons),
  // hide the top-left back button in the inbox header, and prevent SPA navigation to feed.
  static const String _hideDistractionsJs = '''
(function() {
  // 1. Inject global blocker styles
  const styleId = 'nopamin-blocker-style';
  if (!document.getElementById(styleId)) {
    const style = document.createElement('style');
    style.id = styleId;
    style.textContent = `
      /* Hide feed, explore, reels navigation icons */
      a[href="/"],
      a[href="/explore/"],
      a[href^="/reels/"],
      svg[aria-label="Home"],
      svg[aria-label="홈"],
      svg[aria-label="Explore"],
      svg[aria-label="탐색"],
      svg[aria-label="Reels"],
      svg[aria-label="릴스"],
      svg[aria-label="Search"],
      svg[aria-label="검색"],
      svg[aria-label="New post"],
      svg[aria-label="새로운 게시물"] {
        display: none !important;
      }
    `;
    (document.head || document.documentElement).appendChild(style);
  }

  function cleanDistractions() {
    const isInbox = window.location.pathname.startsWith('/direct/inbox') ||
                    window.location.pathname === '/direct/' ||
                    window.location.pathname === '/direct';

    // A. Hide navigation icons (Home, Reels, Explore, etc.)
    const blockedLabels = ["Home", "홈", "Explore", "탐색", "Reels", "릴스", "Search", "검색", "New post", "새로운 게시물"];
    blockedLabels.forEach(label => {
      document.querySelectorAll('svg[aria-label="' + label + '"]').forEach(el => {
        const parent = el.closest('a') || el.closest('div[role="button"]') || el.closest('div[role="tab"]');
        if (parent) {
          parent.style.setProperty('display', 'none', 'important');
        } else {
          el.style.setProperty('display', 'none', 'important');
        }
      });
    });

    // B. Block and hide the top-left back button ONLY when inside the DM inbox
    if (isInbox) {
      // 1) By aria-label
      const backLabels = ["Back", "뒤로", "뒤로 가기", "뒤로가기", "이전", "Home", "홈"];
      backLabels.forEach(label => {
        document.querySelectorAll('svg[aria-label="' + label + '"]').forEach(svg => {
          const btn = svg.closest('a') || svg.closest('button') || svg.closest('div[role="button"]') || svg;
          btn.style.setProperty('display', 'none', 'important');
          btn.style.setProperty('pointer-events', 'none', 'important');
        });
      });

      // 2) Any top-left button/svg in the header (X < 75px, Y < 75px)
      document.querySelectorAll('header div[role="button"], header button, header a, header svg, div[role="navigation"] button, div[role="navigation"] a').forEach(el => {
        const rect = el.getBoundingClientRect();
        if (rect.top >= 0 && rect.top < 75 && rect.left >= 0 && rect.left < 75 && rect.width > 0) {
          el.style.setProperty('display', 'none', 'important');
          el.style.setProperty('pointer-events', 'none', 'important');
          el.style.setProperty('visibility', 'hidden', 'important');
        }
      });

      // 3) Any general SVG with arrow left coordinates in top-left
      document.querySelectorAll('svg').forEach(svg => {
        const rect = svg.getBoundingClientRect();
        if (rect.top >= 0 && rect.top < 75 && rect.left >= 0 && rect.left < 75 && rect.width > 0) {
          const btn = svg.closest('a') || svg.closest('button') || svg.closest('div[role="button"]') || svg;
          btn.style.setProperty('display', 'none', 'important');
          btn.style.setProperty('pointer-events', 'none', 'important');
        }
      });
    }

    // C. Re-route any home links to DM inbox
    document.querySelectorAll('a[href="/"]').forEach(el => {
      el.href = 'https://www.instagram.com/direct/inbox/';
      el.onclick = (e) => {
        e.preventDefault();
        e.stopPropagation();
        window.location.href = 'https://www.instagram.com/direct/inbox/';
      };
    });
  }

  // 2. Intercept click events in capture phase to block clicking the top-left area in inbox
  if (!window._nopaminClickIntercepted) {
    window._nopaminClickIntercepted = true;
    window.addEventListener('click', function(e) {
      const isInbox = window.location.pathname.startsWith('/direct/inbox') ||
                      window.location.pathname === '/direct/' ||
                      window.location.pathname === '/direct';
      if (isInbox) {
        // If user clicks in top-left area where back arrow is located
        if (e.clientX < 75 && e.clientY < 75) {
          e.preventDefault();
          e.stopPropagation();
          e.stopImmediatePropagation();
          return false;
        }

        // If clicking any link targeting root feed
        const link = e.target.closest('a');
        if (link) {
          const href = link.getAttribute('href') || link.pathname;
          if (href === '/' || href === 'https://www.instagram.com/' || href === '') {
            e.preventDefault();
            e.stopPropagation();
            e.stopImmediatePropagation();
            return false;
          }
        }
      }
    }, true);
  }

  // 3. Hook SPA pushState & replaceState to prevent React Router navigating to feed
  if (!window._nopaminHistoryHooked) {
    window._nopaminHistoryHooked = true;
    const origPush = history.pushState;
    history.pushState = function(state, title, url) {
      if (url) {
        const u = url.toString();
        if (u === '/' || u === '' || u === 'https://www.instagram.com/' || u.includes('/explore') || u.includes('/reels')) {
          console.warn('[OnlyDM] Prevented pushState navigation to feed:', u);
          return;
        }
      }
      return origPush.apply(this, arguments);
    };

    const origReplace = history.replaceState;
    history.replaceState = function(state, title, url) {
      if (url) {
        const u = url.toString();
        if (u === '/' || u === '' || u === 'https://www.instagram.com/' || u.includes('/explore') || u.includes('/reels')) {
          console.warn('[OnlyDM] Prevented replaceState navigation to feed:', u);
          return;
        }
      }
      return origReplace.apply(this, arguments);
    };
  }

  cleanDistractions();
  if (!window._nopaminObserverAttached) {
    window._nopaminObserverAttached = true;
    const observer = new MutationObserver(cleanDistractions);
    observer.observe(document.body || document.documentElement, { childList: true, subtree: true });
    // Also run periodically to catch any dynamic React re-renders
    setInterval(cleanDistractions, 500);
  }
})();
''';

  @override
  void initState() {
    super.initState();
    _initWebViewController();
  }

  void _initWebViewController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            setState(() {
              _loadingProgress = progress;
              _isLoading = progress < 100;
            });
            if (progress > 50) {
              _injectDistractionCleaner();
            }
          },
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _hasError = false;
            });
          },
          onPageFinished: (url) {
            setState(() {
              _isLoading = false;
            });
            // Inject distraction-free style and script
            _injectDistractionCleaner();
          },
          onWebResourceError: (error) {
            // Ignore minor resource errors (e.g. tracking scripts blocked)
            if (error.isForMainFrame ?? true) {
              setState(() {
                _hasError = true;
                _errorMessage = error.description;
              });
            }
          },
          onNavigationRequest: (request) {
            return _handleNavigationRequest(request);
          },
        ),
      )
      ..loadRequest(Uri.parse(_dmInboxUrl));
  }

  void _injectDistractionCleaner() {
    _controller.runJavaScript(_hideDistractionsJs).catchError((_) {});
  }

  NavigationDecision _handleNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;

    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();

    // Allow Instagram and authentication domains
    if (host.contains('instagram.com') ||
        host.contains('facebook.com') ||
        host.contains('fbcdn.net') ||
        host.contains('cdninstagram.com')) {
      // Specifically prevent feed, explore, reels, stories
      if (path.startsWith('/explore') ||
          path.startsWith('/reels') ||
          path.startsWith('/stories') ||
          (path.contains('/p/') && !path.startsWith('/direct/'))) {
        debugPrint('[OnlyDM] Dopamine navigation blocked: ${request.url}');
        _controller.loadRequest(Uri.parse(_dmInboxUrl));
        return NavigationDecision.prevent;
      }

      // Root path '/' leads to feed, redirect to direct inbox
      if (path == '/' || path.isEmpty) {
        debugPrint('[OnlyDM] Root feed navigation redirected to DM inbox');
        _controller.loadRequest(Uri.parse(_dmInboxUrl));
        return NavigationDecision.prevent;
      }

      // Allow direct messages, login, challenges, and APIs
      return NavigationDecision.navigate;
    }

    // Disallow external websites inside the DM-only shell
    return NavigationDecision.prevent;
  }

  Future<bool> _onWillPop() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          elevation: 0.5,
          scrolledUnderElevation: 1,
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            tooltip: '뒤로가기',
            onPressed: () async {
              if (await _controller.canGoBack()) {
                await _controller.goBack();
              }
            },
          ),
          title: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFFF58529),
                      Color(0xFFDD2A7B),
                      Color(0xFF8134AF),
                      Color(0xFF515BD4),
                    ],
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                  ),
                ),
                child: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Direct',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'Only DM (Nopamin)',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.home_outlined),
              tooltip: 'DM 홈으로',
              onPressed: () {
                _controller.loadRequest(Uri.parse(_dmInboxUrl));
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '새로고침',
              onPressed: () {
                _controller.reload();
              },
            ),
            const SizedBox(width: 4),
          ],
          bottom: _isLoading
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(
                    value: _loadingProgress > 0 ? _loadingProgress / 100.0 : null,
                    minHeight: 2,
                    color: const Color(0xFFE1306C),
                    backgroundColor: Colors.transparent,
                  ),
                )
              : null,
        ),
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_hasError)
                Container(
                  color: isDark ? const Color(0xFF121212) : Colors.white,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 56,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '인스타그램 연결에 실패했습니다',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage.isNotEmpty
                            ? _errorMessage
                            : '네트워크 연결 상태를 확인한 후 다시 시도해주세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFE1306C),
                        ),
                        onPressed: () {
                          setState(() {
                            _hasError = false;
                          });
                          _controller.loadRequest(Uri.parse(_dmInboxUrl));
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('다시 시도'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
