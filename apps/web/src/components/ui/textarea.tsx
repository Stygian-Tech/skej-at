import * as React from "react";

import { cn } from "@/lib/utils";

export interface TextareaProps
  extends React.TextareaHTMLAttributes<HTMLTextAreaElement> {}

export const Textarea = React.forwardRef<HTMLTextAreaElement, TextareaProps>(
  function Textarea({ className, ...props }, ref) {
    return (
      <textarea
        className={cn(
          "flex min-h-28 w-full resize-none rounded-[1.5rem] border border-input bg-card px-4 py-3 text-base font-semibold leading-6 outline-none transition placeholder:text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50 sm:min-h-36 sm:leading-7",
          className
        )}
        ref={ref}
        {...props}
      />
    );
  }
);
