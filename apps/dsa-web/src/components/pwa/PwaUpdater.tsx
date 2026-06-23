import { useEffect } from 'react';
import { toast } from 'sonner';
import { useRegisterSW } from 'virtual:pwa-register/react';

/**
 * Wires up the vite-plugin-pwa service worker:
 * - Auto-updates on reload (registerType: 'autoUpdate')
 * - When a new SW is waiting, surface a sonner toast with a "Refresh" action
 * - When the app starts working offline, log a one-line confirmation
 */
export function PwaUpdater() {
  const {
    needRefresh: [needRefresh, setNeedRefresh],
    offlineReady: [offlineReady, setOfflineReady],
    updateServiceWorker,
  } = useRegisterSW({
    onRegisteredSW(_swUrl, registration) {
      // Periodically check for an updated SW (every 60 minutes).
      if (!registration) return;
      const intervalId = window.setInterval(() => {
        void registration.update();
      }, 60 * 60 * 1000);
      window.addEventListener('beforeunload', () => window.clearInterval(intervalId));
    },
    onRegisterError(error) {
      console.warn('[PWA] Service worker registration failed:', error);
    },
  });

  useEffect(() => {
    if (!needRefresh) return;
    const id = toast('应用有新版本可用', {
      description: '点击刷新即可加载最新功能与修复。',
      duration: Infinity,
      action: {
        label: '刷新',
        onClick: () => {
          void updateServiceWorker(true);
        },
      },
      onDismiss: () => setNeedRefresh(false),
    });
    return () => {
      toast.dismiss(id);
    };
  }, [needRefresh, setNeedRefresh, updateServiceWorker]);

  useEffect(() => {
    if (!offlineReady) return;
    toast.success('已可离线使用', {
      description: '离线时可继续浏览缓存页面，实时数据需联网刷新。',
      duration: 4000,
    });
    setOfflineReady(false);
  }, [offlineReady, setOfflineReady]);

  return null;
}
