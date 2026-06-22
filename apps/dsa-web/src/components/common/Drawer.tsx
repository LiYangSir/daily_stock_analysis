import type React from 'react';
import { useEffect } from 'react';
import * as DialogPrimitive from '@radix-ui/react-dialog';
import { X } from 'lucide-react';

import { cn } from '../../utils/cn';
import { useUiLanguage } from '../../contexts/UiLanguageContext';

let activeDrawerCount = 0;

interface DrawerProps {
  isOpen: boolean;
  onClose: () => void;
  title?: string;
  children: React.ReactNode;
  width?: string;
  zIndex?: number;
  side?: 'left' | 'right';
  backdropClassName?: string;
}

/**
 * Legacy Drawer contract:
 * - Modal-style: a backdrop dims the rest of the page and clicking it closes the drawer.
 * - body scroll is locked while one or more drawers are open.
 * - Esc closes the drawer.
 * - Title and width / side / zIndex are honored as before.
 */
export const Drawer: React.FC<DrawerProps> = ({
  isOpen,
  onClose,
  title,
  children,
  width = 'max-w-2xl',
  zIndex,
  side = 'right',
  backdropClassName,
}) => {
  const { t } = useUiLanguage();
  const widthClass = width.startsWith('max-w-') ? width : 'max-w-2xl';

  useEffect(() => {
    if (!isOpen) return undefined;
    activeDrawerCount += 1;
    if (activeDrawerCount === 1 && typeof document !== 'undefined') {
      document.body.style.overflow = 'hidden';
    }
    return () => {
      activeDrawerCount = Math.max(0, activeDrawerCount - 1);
      if (activeDrawerCount === 0 && typeof document !== 'undefined') {
        document.body.style.overflow = '';
      }
    };
  }, [isOpen]);

  if (!isOpen) return null;

  return (
    <DialogPrimitive.Root
      open={isOpen}
      onOpenChange={(open) => {
        if (!open) onClose();
      }}
      modal={false}
    >
      <DialogPrimitive.Portal>
        <div
          role="presentation"
          className={cn(
            'fixed inset-0 bg-black/50 backdrop-blur-sm',
            backdropClassName,
          )}
          style={zIndex ? { zIndex: zIndex - 1 } : { zIndex: 49 }}
          onClick={onClose}
        />
        <DialogPrimitive.Content
          onInteractOutside={(event) => event.preventDefault()}
          onPointerDownOutside={(event) => event.preventDefault()}
          onEscapeKeyDown={() => onClose()}
          style={zIndex ? { zIndex } : { zIndex: 50 }}
          className={cn(
            'fixed inset-y-0 flex w-full flex-col bg-background shadow-xl outline-none',
            'duration-200',
            side === 'right'
              ? 'right-0 border-l data-[state=open]:animate-in data-[state=open]:slide-in-from-right data-[state=closed]:animate-out data-[state=closed]:slide-out-to-right'
              : 'left-0 border-r data-[state=open]:animate-in data-[state=open]:slide-in-from-left data-[state=closed]:animate-out data-[state=closed]:slide-out-to-left',
            widthClass,
          )}
        >
          {title ? (
            <div className="flex items-center justify-between border-b px-6 py-4">
              <DialogPrimitive.Title className="text-foreground text-lg font-semibold">
                {title}
              </DialogPrimitive.Title>
              <DialogPrimitive.Close
                className="inline-flex h-9 w-9 items-center justify-center rounded-md border border-input bg-background text-muted-foreground hover:bg-accent hover:text-accent-foreground"
                aria-label={t('common.closeDrawer')}
              >
                <X className="h-4 w-4" />
              </DialogPrimitive.Close>
            </div>
          ) : (
            <DialogPrimitive.Close
              className="absolute right-4 top-4 inline-flex h-9 w-9 items-center justify-center rounded-md border border-input bg-background text-muted-foreground hover:bg-accent hover:text-accent-foreground"
              aria-label={t('common.closeDrawer')}
            >
              <X className="h-4 w-4" />
            </DialogPrimitive.Close>
          )}
          <DialogPrimitive.Description className="sr-only">
            {title ?? ''}
          </DialogPrimitive.Description>
          <div className="flex-1 overflow-y-auto p-6">{children}</div>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
};
