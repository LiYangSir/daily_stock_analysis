import React from 'react';
import { cn } from '../../utils/cn';

type BadgeVariant = 'default' | 'success' | 'warning' | 'danger' | 'info' | 'history';

interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement> {
  children: React.ReactNode;
  variant?: BadgeVariant;
  size?: 'sm' | 'md';
  glow?: boolean;
  className?: string;
  style?: React.CSSProperties;
}

const variantStyles: Record<BadgeVariant, string> = {
  default: 'border-border bg-muted text-muted-foreground',
  success: 'border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300',
  warning: 'border-amber-500/30 bg-amber-500/10 text-amber-700 dark:text-amber-300',
  danger: 'border-destructive/30 bg-destructive/10 text-destructive',
  info: 'border-primary/25 bg-primary/10 text-primary',
  history: 'border-indigo-500/25 bg-indigo-500/10 text-indigo-600 dark:text-indigo-300',
};

const glowStyles: Record<BadgeVariant, string> = {
  default: '',
  success: 'shadow-emerald-500/20',
  warning: 'shadow-amber-500/20',
  danger: 'shadow-destructive/20',
  info: 'shadow-primary/20',
  history: 'shadow-indigo-500/20',
};

export const Badge: React.FC<BadgeProps> = ({
  children,
  variant = 'default',
  size = 'sm',
  glow = false,
  className = '',
  style,
  ...rest
}) => {
  const sizeStyles = size === 'sm' ? 'px-2 py-0.5 text-xs' : 'px-3 py-1 text-sm';

  return (
    <span
      {...rest}
      style={style}
      className={cn(
        'inline-flex items-center gap-1 rounded-full border font-medium',
        sizeStyles,
        variantStyles[variant],
        glow && `shadow-sm ${glowStyles[variant]}`,
        className,
      )}
    >
      {children}
    </span>
  );
};
