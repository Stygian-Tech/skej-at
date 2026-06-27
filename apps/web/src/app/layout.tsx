import type { Metadata } from "next";
import type { Viewport } from "next";

import { EnvironmentBanner } from "@/components/EnvironmentBanner";

import "./globals.css";

const title = "Skej";
const description = "Schedule posts from your PDS.";
const lightInstallIcon = "/icons/skej-icon-light-512.png";
const darkInstallIcon = "/icons/skej-icon-dark-512.png";
const appleTouchIcon = "/icons/skej-apple-touch.png";

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
  manifest: "/manifest-light.webmanifest",
  appleWebApp: {
    capable: true,
    title,
    statusBarStyle: "default",
  },
  icons: {
    icon: [
      {
        url: lightInstallIcon,
        sizes: "512x512",
        type: "image/png",
        media: "(prefers-color-scheme: light)",
      },
      {
        url: darkInstallIcon,
        sizes: "512x512",
        type: "image/png",
        media: "(prefers-color-scheme: dark)",
      },
    ],
    apple: {
      url: appleTouchIcon,
      sizes: "180x180",
      type: "image/png",
    },
  },
};

export const viewport: Viewport = {
  colorScheme: "light dark",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#ffffff" },
    { media: "(prefers-color-scheme: dark)", color: "#111827" },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="antialiased">
      <body>
        <EnvironmentBanner />
        {children}
      </body>
    </html>
  );
}
