import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';

import { SidebarNav } from '../SidebarNav';
import { SidebarProvider } from '@/components/ui/sidebar';

const mockLogout = vi.fn().mockResolvedValue(undefined);
const mockGetAlphaSiftStatus = vi.fn().mockResolvedValue({ enabled: false, available: false, installSpecIsDefault: false });

const completionBadgeState = { value: true };

vi.mock('../../../contexts/AuthContext', () => ({
  useAuth: () => ({
    authEnabled: true,
    logout: mockLogout,
  }),
}));

vi.mock('../../../stores/agentChatStore', () => ({
  useAgentChatStore: (selector: (state: { completionBadge: boolean }) => unknown) =>
    selector({ completionBadge: completionBadgeState.value }),
}));

vi.mock('../../../api/alphasift', () => ({
  ALPHASIFT_CONFIG_CHANGED_EVENT: 'alphasift-config-changed',
  SYSTEM_CONFIG_CHANGED_EVENT: 'dsa-system-config-changed',
  alphasiftApi: {
    getStatus: () => mockGetAlphaSiftStatus(),
  },
}));

function renderSidebar(initialPath: string) {
  return render(
    <MemoryRouter initialEntries={[initialPath]}>
      <SidebarProvider defaultOpen>
        <SidebarNav />
      </SidebarProvider>
    </MemoryRouter>,
  );
}

describe('SidebarNav', () => {
  it('hides the screening navigation item while AlphaSift is disabled', () => {
    mockGetAlphaSiftStatus.mockResolvedValueOnce({ enabled: false, available: false, installSpecIsDefault: false });
    renderSidebar('/');
    expect(screen.queryByRole('link', { name: '选股' })).not.toBeInTheDocument();
  });

  it('shows the screening navigation item when AlphaSift is enabled', async () => {
    mockGetAlphaSiftStatus.mockResolvedValueOnce({ enabled: true, available: false, installSpecIsDefault: false });
    renderSidebar('/');
    expect(await screen.findByRole('link', { name: '选股' })).toHaveAttribute('href', '/screening');
  });

  it('places screening directly after chat when AlphaSift is enabled', async () => {
    mockGetAlphaSiftStatus.mockResolvedValueOnce({ enabled: true, available: false, installSpecIsDefault: false });
    renderSidebar('/');
    await screen.findByRole('link', { name: '选股' });
    const hrefs = screen.getAllByRole('link').map((link) => link.getAttribute('href'));
    expect(hrefs.slice(0, 5)).toEqual(['/', '/chat', '/screening', '/portfolio', '/decision-signals']);
  });

  it('refreshes the screening navigation item after any config save event', async () => {
    mockGetAlphaSiftStatus
      .mockResolvedValueOnce({ enabled: false, available: false, installSpecIsDefault: false })
      .mockResolvedValueOnce({ enabled: true, available: false, installSpecIsDefault: false });

    renderSidebar('/');

    expect(screen.queryByRole('link', { name: '选股' })).not.toBeInTheDocument();
    window.dispatchEvent(new Event('dsa-system-config-changed'));

    expect(await screen.findByRole('link', { name: '选股' })).toHaveAttribute('href', '/screening');
    await waitFor(() => expect(mockGetAlphaSiftStatus.mock.calls.length).toBeGreaterThanOrEqual(2));
  });

  it('shows the shared completion badge only when chat completion is pending', () => {
    completionBadgeState.value = true;

    const { rerender } = renderSidebar('/chat');

    expect(screen.getByTestId('chat-completion-badge')).toBeInTheDocument();
    expect(screen.getByLabelText('问股有新消息')).toBeInTheDocument();

    completionBadgeState.value = false;
    rerender(
      <MemoryRouter initialEntries={['/chat']}>
        <SidebarProvider defaultOpen>
          <SidebarNav />
        </SidebarProvider>
      </MemoryRouter>,
    );

    expect(screen.queryByTestId('chat-completion-badge')).not.toBeInTheDocument();
  });

  it('renders the alerts navigation item and marks it active', () => {
    renderSidebar('/alerts');
    const alertsLink = screen.getByRole('link', { name: '告警' });
    expect(alertsLink).toHaveAttribute('href', '/alerts');
    expect(alertsLink).toHaveAttribute('data-active', 'true');
  });

  it('renders the AI signals navigation item and marks it active', () => {
    renderSidebar('/decision-signals');
    const signalsLink = screen.getByRole('link', { name: 'AI 建议' });
    expect(signalsLink).toHaveAttribute('href', '/decision-signals');
    expect(signalsLink).toHaveAttribute('data-active', 'true');
  });

  it('opens the logout confirmation and confirms logout', async () => {
    renderSidebar('/chat');

    fireEvent.click(screen.getByRole('button', { name: '退出' }));

    expect(await screen.findByRole('heading', { name: '退出登录' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: '确认退出' }));
    expect(mockLogout).toHaveBeenCalled();
  });
});
