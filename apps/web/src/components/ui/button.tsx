import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "@/lib/utils";

const buttonVariants = cva(
  "inline-flex min-h-10 shrink-0 items-center justify-center gap-2 rounded-full border border-transparent px-4 py-2 text-sm font-bold transition active:scale-[0.98] disabled:pointer-events-none disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
  {
    variants: {
      variant: {
        default:
          "bg-primary text-primary-foreground shadow-[0_8px_18px_rgba(255,79,109,0.14)] hover:bg-primary/90",
        secondary:
          "bg-secondary text-secondary-foreground hover:bg-secondary/80",
        outline:
          "border-border bg-card text-foreground hover:bg-muted",
        ghost:
          "text-foreground hover:bg-muted",
        sunny:
          "bg-accent text-accent-foreground shadow-[0_8px_18px_rgba(255,213,64,0.1)] hover:bg-accent/90",
      },
      size: {
        default: "h-11",
        sm: "h-9 px-3 text-xs",
        lg: "h-12 px-5 text-base",
        icon: "size-10 p-0",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {}

export function Button({
  className,
  variant,
  size,
  type = "button",
  ...props
}: ButtonProps) {
  return (
    <button
      type={type}
      className={cn(buttonVariants({ variant, size }), className)}
      {...props}
    />
  );
}

export { buttonVariants };
