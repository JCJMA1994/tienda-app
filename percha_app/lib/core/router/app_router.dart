import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/admin_page.dart';
import '../../features/auth/application/session_controller.dart';
import '../../features/auth/presentation/password_pages.dart';
import '../../features/auth/presentation/two_factor_pages.dart';
import '../../features/messaging/whatsapp_pages.dart';
import '../../features/auth/data/auth_models.dart';
import '../../features/auth/presentation/accept_invitation_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/register_page.dart';
import '../../features/auth/presentation/tenant_picker_page.dart';
import '../../features/billing/presentation/billing_page.dart';
import '../../features/catalog/presentation/import_page.dart';
import '../../features/catalog/presentation/product_detail_page.dart';
import '../../features/catalog/presentation/product_form_page.dart';
import '../../features/catalog/presentation/products_page.dart';
import '../../features/branches/branches_page.dart';
import '../../features/customers/customers_pages.dart';
import '../../features/purchasing/presentation/replenishment_page.dart';
import '../../features/cash/cash_pages.dart';
import '../../features/counts/counts_pages.dart';
import '../../features/promotions/promotions_pages.dart';
import '../../features/reports/presentation/commissions_page.dart';
import '../../features/storefront/storefront_pages.dart';
import '../../features/layaways/layaways_pages.dart';
import '../../features/einvoice/presentation/einvoice_settings_page.dart';
import '../../features/home/presentation/dashboard_page.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/home/presentation/more_page.dart';
import '../../features/notifications/notifications_page.dart';
import '../../features/onboarding/presentation/attributes_step_page.dart';
import '../../features/onboarding/presentation/business_step_page.dart';
import '../../features/pos/presentation/pos_page.dart';
import '../../features/purchasing/presentation/po_detail_page.dart';
import '../../features/purchasing/presentation/po_form_page.dart';
import '../../features/purchasing/presentation/purchases_page.dart';
import '../../features/printing/print_settings_page.dart';
import '../../features/reports/presentation/reports_page.dart';
import '../../features/transfers/presentation/transfers_pages.dart';
import '../../features/pos/presentation/return_page.dart';
import '../../features/pos/presentation/sales_pages.dart';
import '../../features/team/presentation/team_page.dart';
import '../widgets/percha_widgets.dart';

const _publicRoutes = {'/login', '/register', '/invite', '/forgot', '/reset'};
const _entryRoutes = {'/splash', '/login', '/register', '/select-store', '/invite', '/2fa', '/forgot', '/reset'};

/// La navegación se DERIVA del estado de sesión: las pantallas nunca deciden a dónde ir
/// después del login. Así no hay forma de quedar en una pantalla privada sin sesión.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref
    ..listen(sessionProvider, (_, __) => refresh.value++)
    ..onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final loc = state.matchedLocation;
      return switch (session) {
        SessionRestoring() => loc == '/splash' ? null : '/splash',
        SignedOut() => _publicRoutes.contains(loc) ? null : '/login',
        ChoosingTenant() => loc == '/select-store' ? null : '/select-store',
        AwaitingTwoFactor() => loc == '/2fa' ? null : '/2fa',
        SignedIn(:final me, :final isNewStore) => _entryRoutes.contains(loc)
            ? (isNewStore ? '/onboarding/business' : '/home')
            : _allowed(loc, me)
                ? null
                : '/home',
      };
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _Splash()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterPage()),
      GoRoute(path: '/select-store', builder: (_, __) => const TenantPickerPage()),
      GoRoute(path: '/2fa', builder: (_, __) => const TwoFactorPage()),
      GoRoute(path: '/forgot', builder: (_, __) => const ForgotPasswordPage()),
      GoRoute(path: '/reset', builder: (_, state) => ResetPasswordPage(token: state.uri.queryParameters['token'] ?? '')),
      GoRoute(path: '/settings/2fa', builder: (_, __) => const TwoFactorSetupPage()),
      GoRoute(path: '/settings/whatsapp', builder: (_, __) => const WhatsAppSettingsPage()),
      GoRoute(path: '/onboarding/business', builder: (_, __) => const BusinessStepPage()),
      GoRoute(path: '/onboarding/attributes', builder: (_, __) => const AttributesStepPage()),
      GoRoute(
        path: '/invite',
        builder: (_, state) => AcceptInvitationPage(token: state.uri.queryParameters['token'] ?? ''),
      ),
      GoRoute(path: '/pos', builder: (_, __) => const PosPage()),
      GoRoute(path: '/purchases', builder: (_, __) => const PurchasesPage()),
      GoRoute(path: '/purchases/suggestions', builder: (_, __) => const ReplenishmentPage()),
      GoRoute(path: '/purchases/new', builder: (_, __) => const PoFormPage()),
      GoRoute(path: '/purchases/:id', builder: (_, state) => PoDetailPage(orderId: state.pathParameters['id']!)),
      GoRoute(path: '/purchases/:id/edit', builder: (_, state) => PoFormPage(orderId: state.pathParameters['id']!)),
      GoRoute(path: '/purchases/:id/receive', builder: (_, state) => ReceivePage(orderId: state.pathParameters['id']!)),
      GoRoute(path: '/reports', builder: (_, __) => const ReportsPage()),
      GoRoute(path: '/transfers/new', builder: (_, __) => const NewTransferPage()),
      GoRoute(path: '/transfers/:id', builder: (_, state) => TransferDetailPage(id: state.pathParameters['id']!)),
      GoRoute(path: '/billing', builder: (_, __) => const BillingPage()),
      GoRoute(path: '/admin', builder: (_, __) => const AdminPage()),
      GoRoute(path: '/settings/einvoice', builder: (_, __) => const EInvoiceSettingsPage()),
      GoRoute(path: '/team', builder: (_, __) => const TeamPage()),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsPage()),
      GoRoute(path: '/customers', builder: (_, __) => const CustomersPage()),
      GoRoute(path: '/layaways', builder: (_, __) => const LayawaysPage()),
      GoRoute(path: '/layaways/:id', builder: (_, state) => LayawayPage(id: state.pathParameters['id']!)),
      GoRoute(path: '/customers/:id', builder: (_, state) => CustomerPage(id: state.pathParameters['id']!)),
      GoRoute(path: '/settings/printing', builder: (_, __) => const PrintSettingsPage()),
      GoRoute(path: '/settings/branches', builder: (_, __) => const BranchesPage()),
      GoRoute(path: '/settings/catalog', builder: (_, __) => const CatalogSettingsPage()),
      GoRoute(path: '/promotions', builder: (_, __) => const PromotionsPage()),
      GoRoute(path: '/stock-counts', builder: (_, __) => const CountsPage()),
      GoRoute(path: '/stock-counts/:id', builder: (_, state) => CountPage(id: state.pathParameters['id']!)),
      GoRoute(path: '/cash-sessions', builder: (_, __) => const CashSessionsPage()),
      GoRoute(path: '/reports/commissions', builder: (_, __) => const CommissionsPage()),
      GoRoute(path: '/catalog/orders', builder: (_, __) => const CatalogOrdersPage()),
      GoRoute(path: '/catalog/orders/:id', builder: (_, state) => CatalogOrderPage(id: state.pathParameters['id']!)),
      GoRoute(path: '/sales/:id', builder: (_, state) => SaleDetailPage(saleId: state.pathParameters['id']!)),
      GoRoute(path: '/sales/:id/return', builder: (_, state) => ReturnPage(saleId: state.pathParameters['id']!)),
      // Pantallas de producto a pantalla completa (fuera de la barra inferior).
      // '/products/new' e '/import' van antes que '/:id' para que no se lean como un id.
      GoRoute(path: '/products/new', builder: (_, __) => const ProductFormPage()),
      GoRoute(path: '/products/import', builder: (_, __) => const ImportPage()),
      GoRoute(path: '/products/:id', builder: (_, state) => ProductDetailPage(productId: state.pathParameters['id']!)),
      ShellRoute(
        builder: (_, state, child) => HomeShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const DashboardPage()),
          GoRoute(path: '/products', builder: (_, __) => const ProductsPage()),
          GoRoute(path: '/sales', builder: (_, __) => const SalesHistoryPage()),
          GoRoute(path: '/transfers', builder: (_, __) => const TransfersPage()),
          GoRoute(path: '/more', builder: (_, __) => const MorePage()),
        ],
      ),
    ],
  );
});

/// Rutas que exigen un permiso. Protección de UX: la API igual rechazaría la operación.
bool _allowed(String loc, Me me) {
  final can = me.can;
  if (loc == '/admin') return me.isPlatformAdmin;
  if (loc == '/settings/2fa' || loc == '/settings/printing') return true;
  if (loc.startsWith('/customers')) return can('customers.read');
  if (loc.startsWith('/layaways')) return can('sales.read');
  if (loc.startsWith('/catalog/orders')) return can('sales.read');
  if (loc.startsWith('/promotions')) return can('sales.create');
  if (loc.startsWith('/stock-counts')) return can('inventory.adjust');
  if (loc.startsWith('/cash-sessions')) return can('cash.manage');
  if (loc.startsWith('/reports/commissions')) return can('reports.read');
  if (loc.startsWith('/settings')) return can('settings.manage');
  if (loc == '/transfers/new') return can('inventory.adjust');
  if (loc.startsWith('/transfers')) return can('inventory.read');
  if (loc == '/pos') return can('sales.create');
  if (loc == '/reports') return can('reports.read');
  if (loc.startsWith('/sales')) return can('sales.read');
  if (loc == '/purchases/new' || loc == '/purchases/suggestions' || loc.endsWith('/edit')) return can('purchasing.write');
  if (loc.endsWith('/receive')) return can('purchasing.receive');
  if (loc.startsWith('/purchases')) return can('purchasing.read');
  if (loc == '/products/new' || loc == '/products/import') return can('catalog.write');
  return true;
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: PerchaLogo(size: 56)));
}
