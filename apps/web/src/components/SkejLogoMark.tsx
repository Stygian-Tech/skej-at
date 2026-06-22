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
        "grid size-12 shrink-0 overflow-hidden rounded-2xl border border-border bg-white shadow-[0_8px_18px_rgba(35,31,32,0.08)]",
        className
      )}
    >
      <Image
        alt=""
        className="size-full object-cover"
        height={96}
        priority
        src="/icon.png"
        width={96}
      />
    </span>
  );
}
