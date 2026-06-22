import type { Metadata } from "next";
import type { Viewport } from "next";
import Script from "next/script";

import "./globals.css";

const title = "Skej";
const description = "Schedule posts from your PDS.";
const lightInstallIcon = "/icons/skej-icon-light-512.png";
const darkInstallIcon = "/icons/skej-icon-dark-512.png";
const lightAppleTouchIcon = "/icons/skej-apple-touch-light.png";
const darkAppleTouchIcon = "/icons/skej-apple-touch-dark.png";

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
    apple: [
      {
        url: lightAppleTouchIcon,
        sizes: "180x180",
        type: "image/png",
        media: "(prefers-color-scheme: light)",
      },
      {
        url: darkAppleTouchIcon,
        sizes: "180x180",
        type: "image/png",
        media: "(prefers-color-scheme: dark)",
      },
    ],
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
      <Script id="theme-install-icons" strategy="beforeInteractive">
        {`
          (function () {
            var media = window.matchMedia("(prefers-color-scheme: dark)");
            var icons = {
              light: {
                manifest: "/manifest-light.webmanifest",
                icon: "${lightInstallIcon}",
                apple: "${lightAppleTouchIcon}"
              },
              dark: {
                manifest: "/manifest-dark.webmanifest",
                icon: "${darkInstallIcon}",
                apple: "${darkAppleTouchIcon}"
              }
            };

            function upsertLink(selector, attributes) {
              var link = document.querySelector(selector);
              if (!link) {
                link = document.createElement("link");
                document.head.appendChild(link);
              }

              Object.keys(attributes).forEach(function (key) {
                link.setAttribute(key, attributes[key]);
              });
            }

            function applyThemeIcons() {
              var active = media.matches ? icons.dark : icons.light;

              upsertLink('link[rel="manifest"]', {
                rel: "manifest",
                href: active.manifest
              });
              upsertLink('link[data-theme-install-icon="icon"]', {
                "data-theme-install-icon": "icon",
                rel: "icon",
                sizes: "512x512",
                type: "image/png",
                href: active.icon
              });
              upsertLink('link[data-theme-install-icon="apple"]', {
                "data-theme-install-icon": "apple",
                rel: "apple-touch-icon",
                sizes: "180x180",
                href: active.apple
              });
            }

            applyThemeIcons();

            if (typeof media.addEventListener === "function") {
              media.addEventListener("change", applyThemeIcons);
            } else if (typeof media.addListener === "function") {
              media.addListener(applyThemeIcons);
            }
          })();
        `}
      </Script>
      <body>{children}</body>
    </html>
  );
}
