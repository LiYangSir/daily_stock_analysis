import { useRef } from 'react';
import type React from 'react';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { buttonVariants } from '@/components/ui/button';
import { cn } from '../../utils/cn';
import { useUiLanguage } from '../../contexts/UiLanguageContext';

interface ConfirmDialogProps {
  isOpen: boolean;
  title: string;
  message: string;
  confirmText?: string;
  cancelText?: string;
  confirmDisabled?: boolean;
  cancelDisabled?: boolean;
  isDanger?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

/**
 * Legacy ConfirmDialog API backed by shadcn/ui AlertDialog. Preserves prop names
 * and behavior used across the app while picking up the new design language.
 */
export const ConfirmDialog: React.FC<ConfirmDialogProps> = ({
  isOpen,
  title,
  message,
  confirmText,
  cancelText,
  confirmDisabled = false,
  cancelDisabled = false,
  isDanger = false,
  onConfirm,
  onCancel,
}) => {
  const { t } = useUiLanguage();
  const justConfirmedRef = useRef(false);

  return (
    <AlertDialog
      open={isOpen}
      onOpenChange={(open) => {
        if (open) return;
        if (justConfirmedRef.current) {
          justConfirmedRef.current = false;
          return;
        }
        if (!cancelDisabled) {
          onCancel();
        }
      }}
    >
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{title}</AlertDialogTitle>
          <AlertDialogDescription>{message}</AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={cancelDisabled}>
            {cancelText ?? t('common.cancel')}
          </AlertDialogCancel>
          <AlertDialogAction
            disabled={confirmDisabled}
            onClick={() => {
              justConfirmedRef.current = true;
              onConfirm();
            }}
            className={cn(
              isDanger
                ? buttonVariants({ variant: 'destructive' })
                : buttonVariants({ variant: 'default' }),
            )}
          >
            {confirmText ?? t('common.confirm')}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
};
