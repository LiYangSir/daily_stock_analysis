import * as React from 'react';
import { LineChart } from 'lucide-react';

import { cn } from '@/lib/utils';

type LogoProps = {
  className?: string;
  iconClassName?: string;
  textClassName?: string;
  hideText?: boolean;
  appName?: string;
};

export const Logo: React.FC<LogoProps> = ({
  className,
  iconClassName,
  textClassName,
  hideText = false,
  appName = 'Daily Stock Analysis',
}) => {
  return (
    <div className={cn('flex items-center gap-2.5', className)}>
      <div
        className={cn(
          'flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-primary text-primary-foreground shadow-sm ring-1 ring-primary/20',
          iconClassName,
        )}
        aria-hidden
      >
        <LineChart className="h-5 w-5" strokeWidth={2.4} />
      </div>
      {hideText ? null : (
        <div className={cn('flex min-w-0 flex-col leading-tight', textClassName)}>
          <span className="truncate text-[15px] font-semibold tracking-tight text-foreground">
            {appName}
          </span>
          <span className="truncate text-[11px] font-medium text-muted-foreground">
            Intelligent stock workspace
          </span>
        </div>
      )}
    </div>
  );
};
