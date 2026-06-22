import type { Metadata } from "next";

import "./globals.css";

const title = "Skej";
const description = "Schedule posts from your PDS.";

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL ?? "https://skej.at"),
  applicationName: title,
  title: {
    default: title,
    template: `%s · ${title}`,
  },
  description,
  alternates: {
    canonical: "/",
  },
  openGraph: {
    title,
    description,
    url: "https://skej.at",
    siteName: title,
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title,
    description,
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="antialiased" suppressHydrationWarning>
      <body>{children}</body>
    </html>
  );
}
