import React from 'react';
import { useUiLanguage } from '../../contexts/UiLanguageContext';
import { cn } from '../../utils/cn';
import { Button as ShadcnButton, type ButtonProps as ShadcnButtonProps } from '@/components/ui/button';

type LegacyVariant =
  | 'primary'
  | 'secondary'
  | 'outline'
  | 'ghost'
  | 'gradient'
  | 'danger'
  | 'danger-subtle'
  | 'settings-primary'
  | 'settings-secondary'
  | 'action-primary'
  | 'action-secondary'
  | 'home-action-ai'
  | 'home-action-report';

type LegacySize = 'xsm' | 'sm' | 'md' | 'lg' | 'xl';

interface ButtonProps extends Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, 'type'> {
  variant?: LegacyVariant;
  size?: LegacySize;
  isLoading?: boolean;
  loadingText?: string;
  glow?: boolean;
  type?: 'button' | 'submit' | 'reset';
}

const VARIANT_MAP: Record<LegacyVariant, ShadcnButtonProps['variant']> = {
  primary: 'default',
  gradient: 'default',
  'settings-primary': 'default',
  'action-primary': 'default',
  'home-action-ai': 'default',
  secondary: 'secondary',
  'settings-secondary': 'secondary',
  'action-secondary': 'secondary',
  'home-action-report': 'secondary',
  outline: 'outline',
  ghost: 'ghost',
  danger: 'destructive',
  'danger-subtle': 'outline',
};

const VARIANT_EXTRA_CLASS: Partial<Record<LegacyVariant, string>> = {
  gradient: 'bg-gradient-to-r from-primary to-primary/60 text-primary-foreground hover:brightness-105',
  'danger-subtle': 'border-destructive/40 text-destructive hover:bg-destructive/10',
  'home-action-ai': 'bg-primary/10 border border-primary/20 text-primary hover:bg-primary/15',
  'home-action-report': 'bg-secondary text-secondary-foreground hover:bg-secondary/80',
  'action-primary': 'bg-primary/10 border border-primary/20 text-primary hover:bg-primary/15',
  'action-secondary': 'bg-secondary text-secondary-foreground hover:bg-secondary/80',
};

const SIZE_MAP: Record<LegacySize, ShadcnButtonProps['size']> = {
  xsm: 'sm',
  sm: 'sm',
  md: 'default',
  lg: 'lg',
  xl: 'xl',
};

const SIZE_EXTRA_CLASS: Partial<Record<LegacySize, string>> = {
  xsm: 'h-7 px-2.5 text-xs',
};

/**
 * Legacy Button API backed by shadcn/ui Button. Keeps the existing variant/size taxonomy
 * to avoid touching the dozens of callers across pages.
 */
export const Button: React.FC<ButtonProps> = ({
  children,
  variant = 'primary',
  size = 'md',
  isLoading = false,
  loadingText,
  glow = false,
  className,
  disabled,
  type = 'button',
  ...props
}) => {
  const { t } = useUiLanguage();
  const shadcnVariant = VARIANT_MAP[variant] ?? 'default';
  const shadcnSize = SIZE_MAP[size] ?? 'default';

  return (
    <ShadcnButton
      type={type}
      variant={shadcnVariant}
      size={shadcnSize}
      aria-busy={isLoading || undefined}
      data-variant={variant}
      disabled={disabled || isLoading}
      className={cn(
        VARIANT_EXTRA_CLASS[variant],
        SIZE_EXTRA_CLASS[size],
        glow && 'shadow-glow-cyan',
        className,
      )}
      {...props}
    >
      {isLoading ? (
        <span className="flex items-center justify-center gap-2">
          <svg
            className="h-4 w-4 animate-spin text-current"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            aria-hidden
          >
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
            <path
              className="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
            />
          </svg>
          {loadingText ?? t('common.processing')}
        </span>
      ) : (
        children
      )}
    </ShadcnButton>
  );
};
