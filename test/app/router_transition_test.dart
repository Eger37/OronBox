import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('material go_router pages keep a platform transition', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    PageRoute<dynamic>? detailRoute;
    final router = GoRouter(
      navigatorKey: navigatorKey,
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/detail',
          builder: (context, state) => _RouteProbe(
            onRoute: (route) => detailRoute = route,
            child: const Scaffold(body: Text('detail')),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: router),
    );
    await tester.pump();

    router.push('/detail');
    await tester.pump();

    expect(detailRoute, isNotNull);
    expect(detailRoute!.transitionDuration, greaterThan(Duration.zero));
    expect(router.routerDelegate.navigatorKey.currentState!.canPop(), isTrue);
    expect(
      tester.binding.takeException(),
      isNull,
      reason: 'navigation must not fail while probing the route stack',
    );
  });
}

class _RouteProbe extends StatelessWidget {
  const _RouteProbe({required this.onRoute, required this.child});

  final ValueChanged<PageRoute<dynamic>?> onRoute;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    onRoute(
      ModalRoute.of(context) is PageRoute<dynamic>
          ? ModalRoute.of(context)! as PageRoute<dynamic>
          : null,
    );
    return child;
  }
}
