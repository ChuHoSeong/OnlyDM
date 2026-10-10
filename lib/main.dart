import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

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
      title: 'OnlyDM',
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
  Timer? _injectionTimer;

  bool _hasError = false;
  String _errorMessage = '';

  // JavaScript snippet to block dopamine elements, lock reels to a single video,
  // hide inbox top-left back button, and prevent SPA navigation to feed.
  static const String _hideDistractionsJs = '''
(function() {
  function log(msg) {
    if (window.AppLog) {
      window.AppLog.postMessage(msg);
    }
  }

  // 0. Global CSS style injection to instantly hide explore/search/reels/home icons
  const styleId = 'nopamin-blocker-style';
  if (!document.getElementById(styleId)) {
    const style = document.createElement('style');
    style.id = styleId;
    style.textContent = `
      /* Hide all explore & search navigation links (돋보기) */
      a[href*="/explore"],
      a[href^="/explore"],
      a[href*="explore"],
      a[href*="/search"],
      a[href="/"],
      a[href^="/reels/"],
      /* Hide all variations of search, explore, home, reels by aria-label */
      [aria-label*="Search" i],
      [aria-label*="search" i],
      [aria-label*="Explore" i],
      [aria-label*="explore" i],
      [aria-label*="검색"],
      [aria-label*="탐색"],
      [aria-label*="Home" i],
      [aria-label*="홈"],
      [aria-label*="Reels" i],
      [aria-label*="릴스"],
      [aria-label*="New post" i],
      [aria-label*="새로운 게시물"],
      /* Magnifying glass svg paths */
      svg circle[cx="11"][cy="11"],
      svg circle[cx="10"][cy="10"],
      svg path[d*="M19 10.5A8.5"] {
        display: none !important;
        visibility: hidden !important;
        pointer-events: none !important;
      }

      /* Keep search input field visible so user can search chats */
      input[placeholder*="검색"],
      input[type="text"],
      input[type="search"] {
        display: block !important;
        visibility: visible !important;
        pointer-events: auto !important;
      }
    `;
    (document.head || document.documentElement).appendChild(style);
  }

  // 1. Toast notification
  let toastTimer = null;
  function showToast(message) {
    let toast = document.getElementById('nopamin-toast');
    if (!toast) {
      toast = document.createElement('div');
      toast.id = 'nopamin-toast';
      toast.style.cssText = 'position:fixed;bottom:75px;left:50%;transform:translateX(-50%);' +
        'background:rgba(20,20,20,0.92);color:#fff;padding:10px 20px;border-radius:24px;' +
        'font-size:13px;font-weight:600;z-index:9999999;pointer-events:none;' +
        'box-shadow:0 6px 18px rgba(0,0,0,0.5);transition:opacity 0.25s ease;text-align:center;' +
        'white-space:nowrap;border:1px solid rgba(255,255,255,0.2);';
      (document.body || document.documentElement).appendChild(toast);
    }
    toast.textContent = message;
    toast.style.opacity = '1';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      if (toast) toast.style.opacity = '0';
    }, 1800);
  }

  // 2. Hide Navigation icons & DM Inbox Back button
  function cleanDistractions() {
    const path = window.location.pathname;
    const isInbox = path.startsWith('/direct/inbox') || path === '/direct/' || path === '/direct';

    // A. Hide explore / search navigation links (돋보기)
    document.querySelectorAll('a[href*="explore"], a[href*="search"]').forEach(el => {
      el.style.setProperty('display', 'none', 'important');
      el.style.setProperty('visibility', 'hidden', 'important');
      el.style.setProperty('pointer-events', 'none', 'important');
    });

    // B. Hide by aria-label substring across ALL tags (a, svg, div, button)
    const blockedKeywords = ["search", "explore", "검색", "탐색", "home", "홈", "reels", "릴스", "new post", "새로운 게시물"];
    document.querySelectorAll('[aria-label]').forEach(el => {
      if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') return;
      const label = (el.getAttribute('aria-label') || '').toLowerCase();
      for (const kw of blockedKeywords) {
        if (label.includes(kw)) {
          const target = el.closest('a') || el.closest('div[role="button"]') || el.closest('div[role="tab"]') || el;
          target.style.setProperty('display', 'none', 'important');
          target.style.setProperty('visibility', 'hidden', 'important');
          target.style.setProperty('pointer-events', 'none', 'important');
          break;
        }
      }
    });

    // C. Hide any SVG with magnifying glass circle geometry
    document.querySelectorAll('svg').forEach(svg => {
      const isSearchIcon = svg.querySelector('circle[cx="11"], circle[cx="10"], path[d*="M19 10.5"], path[d*="M18.5 10.5"]');
      if (isSearchIcon) {
        const parent = svg.closest('a') || svg.closest('div[role="button"]') || svg.closest('div[role="tab"]');
        if (parent && !parent.querySelector('input')) {
          parent.style.setProperty('display', 'none', 'important');
          parent.style.setProperty('visibility', 'hidden', 'important');
          parent.style.setProperty('pointer-events', 'none', 'important');
        } else {
          svg.style.setProperty('display', 'none', 'important');
        }
      }
    });

    // B. Re-route home links to DM inbox
    document.querySelectorAll('a[href="/"]').forEach(el => {
      el.href = 'https://www.instagram.com/direct/inbox/';
      el.onclick = (e) => {
        e.preventDefault();
        e.stopPropagation();
        window.location.href = 'https://www.instagram.com/direct/inbox/';
      };
    });

    // C. HIDE INBOX TOP-LEFT BACK BUTTON
    if (isInbox) {
      // Find by aria-label
      const backLabels = ["Back", "뒤로", "뒤로 가기", "뒤로가기", "이전", "Home", "홈"];
      backLabels.forEach(label => {
        document.querySelectorAll('svg[aria-label="' + label + '"]').forEach(svg => {
          const btn = svg.closest('div[role="button"]') || svg.closest('button') || svg.closest('a') || svg;
          btn.style.setProperty('display', 'none', 'important');
          btn.style.setProperty('visibility', 'hidden', 'important');
          btn.style.setProperty('pointer-events', 'none', 'important');
        });
      });

      // Find ANY clickable or SVG located in top-left area (X < 70, Y < 70)
      const allTopLeft = document.querySelectorAll('svg, div[role="button"], button, a');
      allTopLeft.forEach(el => {
        const rect = el.getBoundingClientRect();
        if (rect.top >= 0 && rect.top < 70 && rect.left >= 0 && rect.left < 70 && rect.width > 0 && rect.height > 0) {
          el.style.setProperty('display', 'none', 'important');
          el.style.setProperty('visibility', 'hidden', 'important');
          el.style.setProperty('pointer-events', 'none', 'important');
        }
      });
    }

    // D. REELS SCROLL LOCK (친구가 보낸 릴스 무한 스크롤 방지)
    const videos = document.querySelectorAll('video');
    const isReels = path.includes('/reel') || videos.length > 0;

    if (isReels && videos.length > 0) {
      videos.forEach(video => {
        let p = video.parentElement;
        while (p && p !== document.body && p !== document.documentElement) {
          const cs = window.getComputedStyle(p);
          if (cs.overflowY === 'scroll' || cs.overflowY === 'auto' ||
              cs.scrollSnapType.indexOf('mandatory') !== -1 || cs.scrollSnapType.indexOf('proximity') !== -1) {
            p.style.setProperty('overflow', 'hidden', 'important');
            p.style.setProperty('overflow-y', 'hidden', 'important');
            p.style.setProperty('scroll-snap-type', 'none', 'important');
            p.style.setProperty('touch-action', 'none', 'important');
            p.scrollTop = 0;
          }
          p = p.parentElement;
        }
      });
    }
  }

  // 3. Global Scroll Lock for Reels
  if (!window._nopaminScrollLocked) {
    window._nopaminScrollLocked = true;
    window.addEventListener('scroll', function(e) {
      const hasVideo = document.querySelector('video') !== null;
      if (hasVideo || window.location.pathname.includes('/reel')) {
        const target = e.target;
        if (target && target !== document && target.scrollTop > 30) {
          const isComments = target.closest && target.closest('[role="dialog"]');
          if (!isComments) {
            target.scrollTop = 0;
            showToast('친구가 보낸 릴스만 시청할 수 있습니다 (스크롤 차단)');
          }
        }
      }
    }, true);
  }

  // 4. Touch Gestures Interception for Reels
  if (!window._nopaminTouchHooked) {
    window._nopaminTouchHooked = true;
    let touchStartY = 0;
    let touchStartX = 0;
    let isTouchingVideo = false;

    window.addEventListener('touchstart', function(e) {
      if (e.touches && e.touches.length > 0) {
        touchStartY = e.touches[0].clientY;
        touchStartX = e.touches[0].clientX;
        const hasVideo = document.querySelector('video') !== null;
        const isReelUrl = window.location.pathname.includes('/reel');
        const isCommentModal = e.target.closest && (e.target.closest('[role="dialog"] ul') || e.target.closest('[aria-label="댓글"]'));
        isTouchingVideo = (hasVideo || isReelUrl) && !isCommentModal;
      }
    }, { passive: true, capture: true });

    window.addEventListener('touchmove', function(e) {
      if (isTouchingVideo && e.touches && e.touches.length > 0) {
        const currentY = e.touches[0].clientY;
        const currentX = e.touches[0].clientX;
        const deltaY = Math.abs(currentY - touchStartY);
        const deltaX = Math.abs(currentX - touchStartX);

        // If swiping vertically on reel video
        if (deltaY > 6 && deltaY > deltaX) {
          e.preventDefault();
          e.stopPropagation();
          e.stopImmediatePropagation();
          showToast('친구가 보낸 릴스만 시청할 수 있습니다');
          return false;
        }
      }
    }, { passive: false, capture: true });

    // Block mouse wheel and arrow keys on reels
    window.addEventListener('wheel', function(e) {
      const hasVideo = document.querySelector('video') !== null;
      if (hasVideo || window.location.pathname.includes('/reel')) {
        const isCommentModal = e.target.closest && e.target.closest('[role="dialog"] ul');
        if (!isCommentModal) {
          e.preventDefault();
          e.stopPropagation();
          showToast('친구가 보낸 릴스만 시청할 수 있습니다');
        }
      }
    }, { passive: false, capture: true });

    window.addEventListener('keydown', function(e) {
      const hasVideo = document.querySelector('video') !== null;
      if (hasVideo || window.location.pathname.includes('/reel')) {
        if (['ArrowDown', 'ArrowUp', 'PageDown', 'PageUp'].includes(e.key)) {
          e.preventDefault();
          e.stopPropagation();
          showToast('친구가 보낸 릴스만 시청할 수 있습니다');
        }
      }
    }, true);
  }

  // 5. Intercept Click on Inbox Top-Left Back Button
  if (!window._nopaminClickIntercepted) {
    window._nopaminClickIntercepted = true;
    window.addEventListener('click', function(e) {
      const isInbox = window.location.pathname.startsWith('/direct/inbox') ||
                      window.location.pathname === '/direct/' ||
                      window.location.pathname === '/direct';
      if (isInbox) {
        // If clicking in top-left area where back arrow is located (x < 70, y < 70)
        if (e.clientX < 70 && e.clientY < 70) {
          e.preventDefault();
          e.stopPropagation();
          e.stopImmediatePropagation();
          return false;
        }

        const link = e.target.closest ? e.target.closest('a') : null;
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

  // 6. Hook SPA pushState & replaceState
  if (!window._nopaminHistoryHooked) {
    window._nopaminHistoryHooked = true;
    let allowedReelUrl = null;

    const origPush = history.pushState;
    history.pushState = function(state, title, url) {
      if (url) {
        const u = url.toString();
        // Prevent feed or explore or reels explore tab
        if (u === '/' || u === '' || u === 'https://www.instagram.com/' || u.includes('/explore') || u === '/reels/' || u === '/reels') {
          return;
        }
        // If moving to another reel while watching a reel
        if (allowedReelUrl && (u.includes('/reel/') || u.includes('/reels/')) && !u.includes(allowedReelUrl)) {
          showToast('친구가 보낸 릴스만 시청할 수 있습니다');
          return;
        }
        if (u.includes('/reel/') || u.includes('/reels/')) {
          if (!allowedReelUrl) allowedReelUrl = u;
        } else {
          allowedReelUrl = null;
        }
      }
      return origPush.apply(this, arguments);
    };

    const origReplace = history.replaceState;
    history.replaceState = function(state, title, url) {
      if (url) {
        const u = url.toString();
        if (u === '/' || u === '' || u === 'https://www.instagram.com/' || u.includes('/explore') || u === '/reels/' || u === '/reels') {
          return;
        }
        if (allowedReelUrl && (u.includes('/reel/') || u.includes('/reels/')) && !u.includes(allowedReelUrl)) {
          showToast('친구가 보낸 릴스만 시청할 수 있습니다');
          return;
        }
        if (u.includes('/reel/') || u.includes('/reels/')) {
          if (!allowedReelUrl) allowedReelUrl = u;
        } else {
          allowedReelUrl = null;
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
    setInterval(cleanDistractions, 500);
  }
})();
''';

  @override
  void initState() {
    super.initState();
    _initWebViewController();

    // Periodically re-inject to ensure all dynamic SPA page changes stay protected
    _injectionTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (mounted) {
        _injectDistractionCleaner();
      }
    });
  }

  @override
  void dispose() {
    _injectionTimer?.cancel();
    super.dispose();
  }

  void _initWebViewController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'AppLog',
        onMessageReceived: (JavaScriptMessage msg) {
          debugPrint('[OnlyDM Web] ${msg.message}');
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (progress > 40) {
              _injectDistractionCleaner();
            }
          },
          onPageStarted: (url) {
            setState(() {
              _hasError = false;
            });
          },
          onPageFinished: (url) {
            _injectDistractionCleaner();
          },
          onWebResourceError: (error) {
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

    if (_controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
    }
  }

  void _injectDistractionCleaner() {
    _controller.runJavaScript(_hideDistractionsJs).catchError((e) {
      debugPrint('[OnlyDM JS Error] $e');
    });
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
      // General explore, stories, or external posts
      if (path.startsWith('/explore') ||
          path.startsWith('/stories') ||
          (path.contains('/p/') && !path.startsWith('/direct/'))) {
        debugPrint('[OnlyDM] Dopamine navigation blocked: ${request.url}');
        _controller.loadRequest(Uri.parse(_dmInboxUrl));
        return NavigationDecision.prevent;
      }

      // Block general reels exploration feed (/reels or /reels/)
      // But allow specific reel sent in chat (e.g. /reel/<shortcode>/ or /reels/<shortcode>/)
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final isGeneralReelsTab = (path == '/reels' || path == '/reels/') ||
          (segments.length == 1 && segments[0] == 'reels');
      if (isGeneralReelsTab) {
        debugPrint('[OnlyDM] General reels feed blocked: ${request.url}');
        _controller.loadRequest(Uri.parse(_dmInboxUrl));
        return NavigationDecision.prevent;
      }

      // Root path '/' leads to feed, redirect to direct inbox
      if (path == '/' || path.isEmpty) {
        debugPrint('[OnlyDM] Root feed navigation redirected to DM inbox');
        _controller.loadRequest(Uri.parse(_dmInboxUrl));
        return NavigationDecision.prevent;
      }

      // Allow direct messages, specific shared reels, login, challenges, and APIs
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
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
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
