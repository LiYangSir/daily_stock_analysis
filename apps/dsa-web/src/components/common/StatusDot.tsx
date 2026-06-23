import type React from 'react';
import { cn } from '../../utils/cn';

type StatusDotTone = 'success' | 'warning' | 'danger' | 'info' | 'neutral';

interface StatusDotProps extends React.HTMLAttributes<HTMLSpanElement> {
  tone?: StatusDotTone;
  pulse?: boolean;
  className?: string;
}

const TONE_STYLES: Record<StatusDotTone, string> = {
  success: 'bg-success shadow-[0_0_0_3px_color-mix(in_oklab,var(--success)_12%,transparent)]',
  warning: 'bg-warning shadow-[0_0_0_3px_color-mix(in_oklab,var(--warning)_14%,transparent)]',
  danger: 'bg-danger shadow-[0_0_0_3px_color-mix(in_oklab,var(--destructive)_12%,transparent)]',
  info: 'bg-cyan shadow-[0_0_0_3px_color-mix(in_oklab,var(--primary)_12%,transparent)]',
  neutral: 'bg-muted-text shadow-[0_0_0_3px_color-mix(in_oklab,var(--muted-foreground)_12%,transparent)]',
};

export const StatusDot: React.FC<StatusDotProps> = ({
  tone = 'neutral',
  pulse = false,
  className = '',
  ...rest
}) => {
  const hasAccessibleLabel = typeof rest['aria-label'] === 'string' && rest['aria-label'].length > 0;

  return (
    <span
      {...rest}
      aria-hidden={hasAccessibleLabel ? undefined : true}
      className={cn(
        'inline-flex h-2.5 w-2.5 shrink-0 rounded-full',
        TONE_STYLES[tone],
        pulse ? 'animate-pulse' : '',
        className,
      )}
    />
  );
};
