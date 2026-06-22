import React, { useEffect, useState } from 'react';
import {
  Activity,
  BarChart3,
  Bell,
  BriefcaseBusiness,
  Gauge,
  Home,
  LogOut,
  MessageSquareQuote,
  Monitor,
  Moon,
  Search,
  Settings2,
  Sun,
} from 'lucide-react';
import { NavLink, useLocation } from 'react-router-dom';
import { useTheme } from 'next-themes';

import {
  ALPHASIFT_CONFIG_CHANGED_EVENT,
  SYSTEM_CONFIG_CHANGED_EVENT,
  alphasiftApi,
} from '../../api/alphasift';
import { useAuth } from '../../contexts/AuthContext';
import { useAgentChatStore } from '../../stores/agentChatStore';
import { useUiLanguage } from '../../contexts/UiLanguageContext';
import type { UiTextKey } from '../../i18n/uiText';
import { cn } from '../../utils/cn';
import { ConfirmDialog } from '../common/ConfirmDialog';
import { Logo } from './Logo';
import {
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar,
} from '@/components/ui/sidebar';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';

type SidebarNavProps = {
  onNavigate?: () => void;
  /**
   * @deprecated Kept for legacy callers/tests. Real collapsed state comes from the SidebarProvider.
   */
  collapsed?: boolean;
};

type NavItem = {
  key: string;
  labelKey: UiTextKey;
  to: string;
  icon: React.ComponentType<{ className?: string }>;
  exact?: boolean;
  badge?: 'completion';
  group: 'workspace' | 'analysis' | 'account' | 'system';
};

const NAV_ITEMS: NavItem[] = [
  { key: 'home', labelKey: 'layout.nav.home', to: '/', icon: Home, exact: true, group: 'workspace' },
  { key: 'chat', labelKey: 'layout.nav.chat', to: '/chat', icon: MessageSquareQuote, badge: 'completion', group: 'workspace' },
  { key: 'screening', labelKey: 'layout.nav.screening', to: '/screening', icon: Search, group: 'workspace' },
  { key: 'portfolio', labelKey: 'layout.nav.portfolio', to: '/portfolio', icon: BriefcaseBusiness, group: 'workspace' },
  { key: 'decision-signals', labelKey: 'layout.nav.decisionSignals', to: '/decision-signals', icon: Activity, group: 'workspace' },
  { key: 'backtest', labelKey: 'layout.nav.backtest', to: '/backtest', icon: BarChart3, group: 'analysis' },
  { key: 'alerts', labelKey: 'layout.nav.alerts', to: '/alerts', icon: Bell, group: 'analysis' },
  { key: 'usage', labelKey: 'layout.nav.usage', to: '/usage', icon: Gauge, group: 'account' },
  { key: 'settings', labelKey: 'layout.nav.settings', to: '/settings', icon: Settings2, group: 'system' },
];

const GROUP_LABELS: Record<NavItem['group'], UiTextKey | string> = {
  workspace: '工作台',
  analysis: '分析',
  account: '账户',
  system: '系统',
};

const GROUP_LABELS_EN: Record<NavItem['group'], string> = {
  workspace: 'Workspace',
  analysis: 'Analysis',
  account: 'Account',
  system: 'System',
};

export const SidebarNav: React.FC<SidebarNavProps> = ({ onNavigate }) => {
  const { authEnabled, logout } = useAuth();
  const { t, language, setLanguage } = useUiLanguage();
  const completionBadge = useAgentChatStore((state) => state.completionBadge);
  const [showLogoutConfirm, setShowLogoutConfirm] = useState(false);
  const [showAlphaSiftNav, setShowAlphaSiftNav] = useState(false);
  const { setOpenMobile, isMobile, state } = useSidebar();
  const location = useLocation();
  const { theme, resolvedTheme, setTheme } = useTheme();

  useEffect(() => {
    let active = true;
    const refreshAlphaSiftStatus = async () => {
      try {
        const status = await alphasiftApi.getStatus();
        if (active) setShowAlphaSiftNav(status.enabled);
      } catch {
        if (active) setShowAlphaSiftNav(false);
      }
    };
    void refreshAlphaSiftStatus();
    window.addEventListener(ALPHASIFT_CONFIG_CHANGED_EVENT, refreshAlphaSiftStatus);
    window.addEventListener(SYSTEM_CONFIG_CHANGED_EVENT, refreshAlphaSiftStatus);
    return () => {
      active = false;
      window.removeEventListener(ALPHASIFT_CONFIG_CHANGED_EVENT, refreshAlphaSiftStatus);
      window.removeEventListener(SYSTEM_CONFIG_CHANGED_EVENT, refreshAlphaSiftStatus);
    };
  }, []);

  const navItems = showAlphaSiftNav
    ? NAV_ITEMS
    : NAV_ITEMS.filter((item) => item.key !== 'screening');

  const grouped = (['workspace', 'analysis', 'account', 'system'] as const).map((group) => ({
    group,
    items: navItems.filter((item) => item.group === group),
  })).filter((g) => g.items.length > 0);

  const handleNavigate = () => {
    if (isMobile) setOpenMobile(false);
    onNavigate?.();
  };

  const isItemActive = (item: NavItem) => {
    if (item.exact) return location.pathname === item.to;
    return location.pathname === item.to || location.pathname.startsWith(`${item.to}/`);
  };

  const visualTheme = resolvedTheme ?? 'light';
  const ThemeIcon = visualTheme === 'light' ? Sun : Moon;
  const collapsed = state === 'collapsed' && !isMobile;

  return (
    <>
      <SidebarHeader className="border-b border-sidebar-border px-3 py-3.5">
        <Logo hideText={collapsed} />
      </SidebarHeader>

      <SidebarContent>
        <nav aria-label={t('layout.mainNav')} className="contents">
          {grouped.map(({ group, items }) => (
            <SidebarGroup key={group}>
            <SidebarGroupLabel>
              {language === 'en' ? GROUP_LABELS_EN[group] : GROUP_LABELS[group]}
            </SidebarGroupLabel>
            <SidebarGroupContent>
              <SidebarMenu>
                {items.map((item) => {
                  const Icon = item.icon;
                  const label = t(item.labelKey);
                  const active = isItemActive(item);
                  return (
                    <SidebarMenuItem key={item.key}>
                      <SidebarMenuButton
                        asChild
                        isActive={active}
                        tooltip={label}
                      >
                        <NavLink to={item.to} onClick={handleNavigate} end={item.exact} aria-label={label}>
                          <Icon className="h-4 w-4" />
                          <span>{label}</span>
                          {item.badge === 'completion' && completionBadge ? (
                            <span
                              data-testid="chat-completion-badge"
                              aria-label={t('layout.newChatMessage')}
                              className="ml-auto h-2 w-2 shrink-0 rounded-full bg-primary shadow-[0_0_0_2px_var(--sidebar)]"
                            />
                          ) : null}
                        </NavLink>
                      </SidebarMenuButton>
                    </SidebarMenuItem>
                  );
                })}
              </SidebarMenu>
            </SidebarGroupContent>
          </SidebarGroup>
          ))}
        </nav>
      </SidebarContent>

      <SidebarFooter className="gap-1 border-t border-sidebar-border">
        <SidebarMenu>
          <SidebarMenuItem>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <SidebarMenuButton tooltip={t('theme.theme')}>
                  <ThemeIcon className="h-4 w-4" />
                  <span>{t('theme.theme')}</span>
                </SidebarMenuButton>
              </DropdownMenuTrigger>
              <DropdownMenuContent side="right" align="end" className="min-w-[8rem]">
                <DropdownMenuLabel>{t('theme.menu')}</DropdownMenuLabel>
                <DropdownMenuSeparator />
                <DropdownMenuItem onClick={() => setTheme('light')} className={cn(theme === 'light' && 'bg-accent')}>
                  <Sun className="h-4 w-4" />
                  <span>{t('theme.light')}</span>
                </DropdownMenuItem>
                <DropdownMenuItem onClick={() => setTheme('dark')} className={cn(theme === 'dark' && 'bg-accent')}>
                  <Moon className="h-4 w-4" />
                  <span>{t('theme.dark')}</span>
                </DropdownMenuItem>
                <DropdownMenuItem onClick={() => setTheme('system')} className={cn(theme === 'system' && 'bg-accent')}>
                  <Monitor className="h-4 w-4" />
                  <span>{t('theme.system')}</span>
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </SidebarMenuItem>
          <SidebarMenuItem>
            <SidebarMenuButton
              onClick={() => setLanguage(language === 'zh' ? 'en' : 'zh')}
              tooltip={t('language.uiLanguage')}
            >
              <Globe2Icon />
              <span>{language === 'zh' ? t('language.current') : t('language.english')}</span>
            </SidebarMenuButton>
          </SidebarMenuItem>
          {authEnabled ? (
            <SidebarMenuItem>
              <SidebarMenuButton
                onClick={() => setShowLogoutConfirm(true)}
                tooltip={t('layout.logout')}
              >
                <LogOut className="h-4 w-4" />
                <span>{t('layout.logout')}</span>
              </SidebarMenuButton>
            </SidebarMenuItem>
          ) : null}
        </SidebarMenu>
      </SidebarFooter>

      <ConfirmDialog
        isOpen={showLogoutConfirm}
        title={t('layout.logoutTitle')}
        message={t('layout.logoutMessage')}
        confirmText={t('layout.logoutConfirm')}
        cancelText={t('common.cancel')}
        isDanger
        onConfirm={() => {
          setShowLogoutConfirm(false);
          onNavigate?.();
          void logout();
        }}
        onCancel={() => setShowLogoutConfirm(false)}
      />
    </>
  );
};

function Globe2Icon() {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      className="h-4 w-4"
      aria-hidden
    >
      <path d="M21.54 15H17a2 2 0 0 0-2 2v4.54" />
      <path d="M7 3.34V5a3 3 0 0 0 3 3v0a2 2 0 0 1 2 2v0c0 1.1.9 2 2 2v0a2 2 0 0 0 2-2v0c0-1.1.9-2 2-2h3.17" />
      <path d="M11 21.95V18a2 2 0 0 0-2-2v0a2 2 0 0 1-2-2v-1a2 2 0 0 0-2-2H2.05" />
      <circle cx="12" cy="12" r="10" />
    </svg>
  );
}
