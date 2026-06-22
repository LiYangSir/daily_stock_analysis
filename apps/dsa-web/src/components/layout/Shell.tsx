import type React from 'react';
import { useState } from 'react';
import { Outlet, useLocation } from 'react-router-dom';
import { PanelLeft } from 'lucide-react';

import { SidebarProvider } from '@/components/ui/sidebar';
import { Separator } from '@/components/ui/separator';
import { Button } from '@/components/ui/button';
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbList,
  BreadcrumbPage,
} from '@/components/ui/breadcrumb';

import { SidebarNav } from './SidebarNav';
import { useUiLanguage } from '../../contexts/UiLanguageContext';
import type { UiTextKey } from '../../i18n/uiText';
import { cn } from '../../utils/cn';

type ShellProps = {
  children?: React.ReactNode;
};

const ROUTE_TITLES: Record<string, { title: UiTextKey; description: UiTextKey }> = {
  '/': { title: 'layout.route.home.title', description: 'layout.route.home.description' },
  '/chat': { title: 'layout.route.chat.title', description: 'layout.route.chat.description' },
  '/portfolio': { title: 'layout.route.portfolio.title', description: 'layout.route.portfolio.description' },
  '/screening': { title: 'layout.route.screening.title', description: 'layout.route.screening.description' },
  '/backtest': { title: 'layout.route.backtest.title', description: 'layout.route.backtest.description' },
  '/alerts': { title: 'layout.route.alerts.title', description: 'layout.route.alerts.description' },
  '/usage': { title: 'layout.route.usage.title', description: 'layout.route.usage.description' },
  '/decision-signals': {
    title: 'layout.route.decisionSignals.title',
    description: 'layout.route.decisionSignals.description',
  },
  '/settings': { title: 'layout.route.settings.title', description: 'layout.route.settings.description' },
};

export const Shell: React.FC<ShellProps> = ({ children }) => {
  const { t } = useUiLanguage();
  const location = useLocation();
  const current = ROUTE_TITLES[location.pathname];
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [mobileOpen, setMobileOpen] = useState(false);

  // Floating card width: 16rem (open) / 4.5rem (collapsed). Outer aside also has p-3 (0.75rem each side).
  const sidebarShellWidth = sidebarOpen ? '16rem' : '4.5rem';

  return (
    <SidebarProvider open={sidebarOpen} onOpenChange={setSidebarOpen}>
      <div
        className="relative min-h-svh w-full bg-background"
        style={{ ['--shell-sidebar' as string]: sidebarShellWidth }}
      >
        {/* Desktop floating sidebar */}
        <aside
          aria-label={t('layout.desktopSidebar')}
          className="fixed inset-y-0 left-0 z-40 hidden p-3 md:flex"
          style={{ width: 'var(--shell-sidebar)', transition: 'width 200ms ease' }}
        >
          <div
            className={cn(
              'flex h-full w-full flex-col overflow-hidden',
              'rounded-2xl border border-sidebar-border bg-sidebar/70',
              'backdrop-blur-xl backdrop-saturate-150 text-sidebar-foreground',
              'shadow-[0_8px_30px_-6px_color-mix(in_oklab,var(--foreground)_18%,transparent),0_2px_6px_-2px_color-mix(in_oklab,var(--foreground)_10%,transparent)]',
            )}
          >
            <SidebarNav />
          </div>
        </aside>

        {/* Mobile drawer sidebar */}
        {mobileOpen ? (
          <div className="fixed inset-0 z-50 md:hidden" onClick={() => setMobileOpen(false)}>
            <div className="absolute inset-0 bg-black/40 backdrop-blur-sm" />
            <aside
              className="absolute inset-y-0 left-0 flex w-72 p-3"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex h-full w-full flex-col overflow-hidden rounded-2xl border border-sidebar-border bg-sidebar text-sidebar-foreground shadow-2xl">
                <SidebarNav onNavigate={() => setMobileOpen(false)} />
              </div>
            </aside>
          </div>
        ) : null}

        {/* Main column — reserves left space equal to floating sidebar width on md+ */}
        <div className="flex min-h-svh w-full flex-col pl-0 md:pl-[var(--shell-sidebar)]">
          <header className="sticky top-0 z-30 flex h-14 shrink-0 items-center gap-2 border-b bg-background/80 px-4 backdrop-blur supports-[backdrop-filter]:bg-background/60">
            <Button
              variant="ghost"
              size="icon"
              className="-ml-1 h-9 w-9"
              aria-label={t('layout.openNav')}
              onClick={() => {
                if (window.matchMedia('(min-width: 768px)').matches) {
                  setSidebarOpen((value) => !value);
                } else {
                  setMobileOpen(true);
                }
              }}
            >
              <PanelLeft className="h-4 w-4" />
            </Button>
            <Separator orientation="vertical" className="mr-2 h-5" />
            <div className="flex min-w-0 flex-1 flex-col leading-tight">
              <Breadcrumb>
                <BreadcrumbList>
                  <BreadcrumbItem>
                    <BreadcrumbPage className="truncate text-sm font-semibold text-foreground">
                      {current ? t(current.title) : t('layout.appFallbackTitle')}
                    </BreadcrumbPage>
                  </BreadcrumbItem>
                </BreadcrumbList>
              </Breadcrumb>
              <span className="truncate text-xs text-muted-foreground">
                {current ? t(current.description) : t('layout.appFallbackDescription')}
              </span>
            </div>
          </header>
          <main className="flex flex-1 flex-col min-w-0 px-4 py-4 sm:px-6 sm:py-5 lg:px-8">
            {children ?? <Outlet />}
          </main>
        </div>
      </div>
    </SidebarProvider>
  );
};
