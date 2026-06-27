import Image from "next/image";

import { cn } from "@/lib/utils";

interface SkejLogoMarkProps {
  className?: string;
}

export function SkejLogoMark({ className }: SkejLogoMarkProps) {
  return (
    <span
      aria-hidden="true"
      className={cn(
        "grid size-12 shrink-0 overflow-hidden rounded-2xl border border-border bg-white shadow-[0_8px_18px_rgba(35,31,32,0.08)] dark:bg-[#08070a]",
        className
      )}
    >
      <Image
        alt=""
        className="size-full object-cover dark:hidden"
        height={96}
        priority
        src="/icons/skej-icon-light-192.png"
        width={96}
      />
      <Image
        alt=""
        className="hidden size-full object-cover dark:block"
        height={96}
        priority
        src="/icons/skej-icon-dark-192.png"
        width={96}
      />
    </span>
  );
}
