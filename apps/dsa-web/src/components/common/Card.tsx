import type React from 'react';
import { cn } from '../../utils/cn';
import { Card as ShadcnCard } from '@/components/ui/card';

interface CardProps {
  title?: string;
  subtitle?: string;
  children: React.ReactNode;
  className?: string;
  style?: React.CSSProperties;
  variant?: 'default' | 'bordered' | 'gradient';
  hoverable?: boolean;
  padding?: 'none' | 'sm' | 'md' | 'lg';
}

/**
 * Legacy Card API backed by shadcn/ui Card. Maintains the same public surface
 * (title/subtitle/variant/hoverable/padding) so existing callers stay untouched.
 */
export const Card: React.FC<CardProps> = ({
  title,
  subtitle,
  children,
  className,
  style,
  variant = 'default',
  hoverable = false,
  padding = 'md',
}) => {
  const paddingStyles = {
    none: 'p-0',
    sm: 'p-4',
    md: 'p-5',
    lg: 'p-6',
  } as const;

  const variantStyles = {
    default: '',
    bordered: 'border-border',
    gradient:
      'bg-gradient-to-br from-primary/5 via-card to-card border-primary/15 shadow-md',
  } as const;

  return (
    <ShadcnCard
      style={style}
      className={cn(
        'overflow-hidden',
        paddingStyles[padding],
        variantStyles[variant],
        hoverable && 'cursor-pointer transition-all hover:border-primary/40 hover:shadow-md',
        className,
      )}
    >
      {(title || subtitle) && (
        <div className="mb-3">
          {subtitle ? (
            <span className="text-[11px] font-medium uppercase tracking-wider text-muted-foreground">
              {subtitle}
            </span>
          ) : null}
          {title ? (
            <h3 className="mt-1 text-lg font-semibold text-foreground">{title}</h3>
          ) : null}
        </div>
      )}
      {children}
    </ShadcnCard>
  );
};
